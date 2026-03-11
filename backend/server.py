"""
Incredere VoiceAI - Backend Server
Hybrid Streaming Pipeline: Deepgram (STT) → Gemini (LLM) → Cartesia (TTS)
"""

import asyncio
import json
import os
import logging
import time

from dotenv import load_dotenv
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
import websockets

from groq import AsyncGroq
from cartesia import AsyncCartesia

load_dotenv(os.path.join(os.path.dirname(__file__), '..', '.env'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("voiceai")

DEEPGRAM_API_KEY = os.getenv("DEEPGRAM_API_KEY")
GROQ_API_KEY = os.getenv("GROQ_API_KEY")
CARTESIA_API_KEY = os.getenv("CARTESIA_API_KEY")

SYSTEM_PROMPT = """You are a friendly, natural-sounding AI voice assistant called "VoiceAI" by Incredere.
You are having a real-time voice conversation with the user.

Rules:
- Keep responses SHORT (1-3 sentences max) — this is a voice conversation, not a text chat.
- Be warm, natural, and conversational — like talking to a friend.
- Use casual language, contractions (I'm, don't, that's), and natural speech patterns.
- Never use markdown, bullet points, or formatting — you're speaking, not writing.
- If you don't understand something, ask briefly to clarify.
- Show personality — be helpful but also engaging and sometimes witty.
- Match the energy of the user — if they're excited, be excited back.
"""

VOICES = {
    "aria": {
        "id": "6ccbfb76-1fc6-48f7-b71d-91ac6298247b",
        "name": "Aria",
        "gender": "female",
    },
    "max": {
        "id": "a0e99841-438c-4a64-b679-ae501e7d6091",
        "name": "Max",
        "gender": "male",
    },
}
DEFAULT_VOICE = "aria"
CARTESIA_MODEL_ID = "sonic-2"

DEEPGRAM_WS_URL = "wss://api.deepgram.com/v1/listen"

# Pricing per unit
PRICE_STT_PER_MIN = 0.0043       # Deepgram Nova-3
PRICE_LLM_INPUT_PER_1M = 0.59    # Groq Llama 3.3 70B input
PRICE_LLM_OUTPUT_PER_1M = 0.79   # Groq Llama 3.3 70B output
PRICE_TTS_PER_1K_CHARS = 0.06    # Cartesia Sonic-2

app = FastAPI(title="Incredere VoiceAI Server")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
async def health():
    return {"status": "ok", "service": "Incredere VoiceAI"}


@app.get("/voices")
async def get_voices():
    return {"voices": VOICES}


class VoiceSession:
    """Manages a single voice conversation session."""

    def __init__(self, websocket: WebSocket, voice_key: str = DEFAULT_VOICE):
        self.ws = websocket
        self.voice = VOICES.get(voice_key, VOICES[DEFAULT_VOICE])
        self.conversation_history = []
        self.is_speaking = False
        self.cancel_speech = False
        self.dg_ws = None
        self.transcript_buffer = ""
        self.silence_task = None

        # Usage tracking
        self.session_start = time.time()
        self.stt_audio_bytes = 0
        self.llm_input_tokens = 0
        self.llm_output_tokens = 0
        self.llm_calls = 0
        self.tts_characters = 0

        logger.info(f"Voice selected: {self.voice['name']} ({self.voice['gender']})")

    async def _connect_deepgram(self):
        """Connect (or reconnect) to Deepgram WebSocket."""
        dg_params = (
            f"?model=nova-3&language=en&encoding=linear16&sample_rate=16000"
            f"&channels=1&interim_results=true&utterance_end_ms=1200"
            f"&vad_events=true&endpointing=300"
        )
        dg_url = DEEPGRAM_WS_URL + dg_params
        extra_headers = {"Authorization": f"Token {DEEPGRAM_API_KEY}"}

        self.dg_ws = await websockets.connect(
            dg_url,
            additional_headers=extra_headers,
            ping_interval=5,
            ping_timeout=10,
        )
        logger.info("Deepgram WebSocket connected")

    async def _keepalive_deepgram(self):
        """Send keepalive messages to Deepgram to prevent timeout."""
        try:
            while True:
                await asyncio.sleep(8)
                if self.dg_ws and self.dg_ws.state.name == "OPEN":
                    # Send a KeepAlive message per Deepgram docs
                    await self.dg_ws.send(json.dumps({"type": "KeepAlive"}))
        except asyncio.CancelledError:
            pass
        except Exception as e:
            logger.error(f"Keepalive error: {e}")

    async def start(self):
        """Start the voice session."""
        logger.info("Voice session started")

        try:
            await self._connect_deepgram()
        except Exception as e:
            logger.error(f"Failed to connect to Deepgram: {e}")
            await self.ws.send_json({"type": "error", "message": f"Deepgram connection failed: {e}"})
            return

        # Start background tasks
        dg_listener = asyncio.create_task(self._listen_deepgram())
        dg_keepalive = asyncio.create_task(self._keepalive_deepgram())

        try:
            while True:
                data = await self.ws.receive()

                if data.get("type") == "websocket.disconnect":
                    break

                if "bytes" in data:
                    # Track STT audio bytes
                    self.stt_audio_bytes += len(data["bytes"])
                    # Forward audio to Deepgram, reconnect if needed
                    if self.dg_ws and self.dg_ws.state.name == "OPEN":
                        await self.dg_ws.send(data["bytes"])
                    else:
                        # Reconnect Deepgram
                        logger.info("Deepgram disconnected, reconnecting...")
                        dg_listener.cancel()
                        try:
                            await self._connect_deepgram()
                            dg_listener = asyncio.create_task(self._listen_deepgram())
                            await self.dg_ws.send(data["bytes"])
                        except Exception as e:
                            logger.error(f"Deepgram reconnect failed: {e}")
                elif "text" in data:
                    msg = json.loads(data["text"])
                    if msg.get("type") == "interrupt":
                        await self._handle_interrupt()
                    elif msg.get("type") == "text_input":
                        await self._process_user_input(msg["text"])
                    elif msg.get("type") == "request_summary":
                        summary = self._build_session_summary()
                        await self.ws.send_json(summary)
                        logger.info(f"Session cost: ${summary['total_cost']:.6f}")

        except WebSocketDisconnect:
            logger.info("Client disconnected")
        finally:
            dg_listener.cancel()
            dg_keepalive.cancel()
            if self.dg_ws:
                await self.dg_ws.close()
            logger.info("Voice session ended")

    async def _listen_deepgram(self):
        """Listen for transcription results from Deepgram."""
        try:
            async for message in self.dg_ws:
                data = json.loads(message)

                if data.get("type") == "Results":
                    channel = data.get("channel", {})
                    alternatives = channel.get("alternatives", [])
                    if not alternatives:
                        continue

                    transcript = alternatives[0].get("transcript", "")
                    if not transcript:
                        continue

                    is_final = data.get("is_final", False)

                    if is_final:
                        self.transcript_buffer += transcript + " "
                        logger.info(f"[STT Final] {transcript}")

                        await self.ws.send_json({
                            "type": "transcript",
                            "text": transcript,
                            "is_final": True,
                        })

                        # Reset silence timer
                        if self.silence_task:
                            self.silence_task.cancel()
                        self.silence_task = asyncio.create_task(
                            self._silence_timeout()
                        )
                    else:
                        await self.ws.send_json({
                            "type": "transcript",
                            "text": transcript,
                            "is_final": False,
                        })

                        # Interrupt AI if user starts talking
                        if self.is_speaking and len(transcript.strip()) > 3:
                            await self._handle_interrupt()

                elif data.get("type") == "UtteranceEnd":
                    # Deepgram detected end of utterance
                    if self.transcript_buffer.strip():
                        if self.silence_task:
                            self.silence_task.cancel()
                        user_text = self.transcript_buffer.strip()
                        self.transcript_buffer = ""
                        asyncio.create_task(self._process_user_input(user_text))

        except websockets.exceptions.ConnectionClosed:
            logger.info("Deepgram connection closed")
        except asyncio.CancelledError:
            pass
        except Exception as e:
            logger.error(f"Deepgram listener error: {e}")

    async def _silence_timeout(self):
        """After user stops speaking, process their complete utterance."""
        await asyncio.sleep(0.8)

        if self.transcript_buffer.strip():
            user_text = self.transcript_buffer.strip()
            self.transcript_buffer = ""
            await self._process_user_input(user_text)

    async def _handle_interrupt(self):
        """User started speaking while AI was talking — stop AI."""
        if self.is_speaking:
            logger.info("[Interrupt] User interrupted AI")
            self.cancel_speech = True
            self.is_speaking = False
            await self.ws.send_json({"type": "stop_audio"})

    async def _process_user_input(self, user_text: str):
        """Send user text to LLM, then TTS, then stream audio back."""
        logger.info(f"[User] {user_text}")

        self.conversation_history.append({
            "role": "user",
            "content": user_text,
        })

        if len(self.conversation_history) > 20:
            self.conversation_history = self.conversation_history[-20:]

        await self.ws.send_json({"type": "ai_thinking"})

        try:
            self.cancel_speech = False
            ai_text = await self._get_llm_response(user_text)

            if self.cancel_speech:
                return

            logger.info(f"[AI] {ai_text}")

            self.conversation_history.append({
                "role": "assistant",
                "content": ai_text,
            })

            await self.ws.send_json({
                "type": "ai_text",
                "text": ai_text,
            })

            if not self.cancel_speech:
                await self._speak(ai_text)

        except Exception as e:
            logger.error(f"Processing error: {e}")
            await self.ws.send_json({
                "type": "error",
                "message": str(e),
            })

    async def _get_llm_response(self, user_text: str) -> str:
        """Get response from Groq LLM."""
        client = AsyncGroq(api_key=GROQ_API_KEY)

        messages = [
            {"role": "system", "content": SYSTEM_PROMPT},
            *self.conversation_history,
        ]

        response = await client.chat.completions.create(
            model="llama-3.3-70b-versatile",
            messages=messages,
            max_tokens=150,
            temperature=0.7,
        )

        # Track LLM token usage
        if response.usage:
            self.llm_input_tokens += response.usage.prompt_tokens or 0
            self.llm_output_tokens += response.usage.completion_tokens or 0
            self.llm_calls += 1

        return response.choices[0].message.content.strip()

    def _build_session_summary(self) -> dict:
        """Build cost summary for this session."""
        duration_sec = time.time() - self.session_start
        # STT: 16-bit mono 16kHz = 32000 bytes/sec
        stt_duration_min = (self.stt_audio_bytes / 32000) / 60
        stt_cost = stt_duration_min * PRICE_STT_PER_MIN

        llm_input_cost = (self.llm_input_tokens / 1_000_000) * PRICE_LLM_INPUT_PER_1M
        llm_output_cost = (self.llm_output_tokens / 1_000_000) * PRICE_LLM_OUTPUT_PER_1M
        llm_cost = llm_input_cost + llm_output_cost

        tts_cost = (self.tts_characters / 1000) * PRICE_TTS_PER_1K_CHARS

        total_cost = stt_cost + llm_cost + tts_cost

        return {
            "type": "session_summary",
            "session_duration_sec": round(duration_sec, 1),
            "stt_duration_min": round(stt_duration_min, 3),
            "stt_cost": round(stt_cost, 6),
            "llm_input_tokens": self.llm_input_tokens,
            "llm_output_tokens": self.llm_output_tokens,
            "llm_calls": self.llm_calls,
            "llm_cost": round(llm_cost, 6),
            "tts_characters": self.tts_characters,
            "tts_cost": round(tts_cost, 6),
            "total_cost": round(total_cost, 6),
            "voice": self.voice["name"],
        }

    async def _speak(self, text: str):
        """Convert text to speech using Cartesia and stream audio to client."""
        self.is_speaking = True
        # Track TTS characters
        self.tts_characters += len(text)

        try:
            cartesia = AsyncCartesia(api_key=CARTESIA_API_KEY)

            chunk_iter = await cartesia.tts.bytes(
                model_id=CARTESIA_MODEL_ID,
                transcript=text,
                voice={"mode": "id", "id": self.voice["id"]},
                output_format={
                    "container": "raw",
                    "encoding": "pcm_s16le",
                    "sample_rate": 24000,
                },
            )

            async for audio_chunk in chunk_iter:
                if self.cancel_speech:
                    logger.info("[TTS] Speech cancelled by interrupt")
                    break
                await self.ws.send_bytes(audio_chunk)

            if not self.cancel_speech:
                await self.ws.send_json({"type": "audio_done"})

            await cartesia.close()

        except Exception as e:
            logger.error(f"TTS error: {e}")
        finally:
            self.is_speaking = False

    async def _on_dg_error(self, error):
        logger.error(f"Deepgram error: {error}")


@app.websocket("/ws/voice/{voice_key}")
async def voice_endpoint(websocket: WebSocket, voice_key: str = DEFAULT_VOICE):
    await websocket.accept()
    logger.info(f"Client connected with voice: {voice_key}")

    session = VoiceSession(websocket, voice_key)
    await session.start()


if __name__ == "__main__":
    uvicorn.run(
        "server:app",
        host=os.getenv("SERVER_HOST", "0.0.0.0"),
        port=int(os.getenv("SERVER_PORT", 8000)),
        reload=True,
    )
