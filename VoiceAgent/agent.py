#!/usr/bin/env python3
"""LiveKit voice agent. Tools RPC to the iOS app; this process never computes exposure."""

from __future__ import annotations

import json
import os

from dotenv import load_dotenv
from livekit.agents import Agent, AgentServer, AgentSession, JobContext, RunContext, ToolError, cli, function_tool, get_job_context
from livekit.plugins import openai, silero

load_dotenv()

INSTRUCTIONS = """
You are Resilio's voice planner. You do not compute air quality, exposure, heat risk, or safer routes.
After the user speaks, call planning_turn with their words. Then speak only facts from the tool snapshot.
Never invent PM2.5, temperature, or percent reductions. Never rank nearby paths or trails.
Never ask for medical conditions, medications, age, or other health details.
If the snapshot says routeComparisonAvailable is false, say you cannot pick a cleaner path.
Ask for missing fields listed in the snapshot. Confirm before save_plan.
Keep spoken replies short. The phone already shows the full text.
"""


async def rpc(method: str, payload: dict) -> dict:
    room = get_job_context().room
    if not room.remote_participants:
        raise ToolError("The iOS planner is not connected yet.")
    identity = next(iter(room.remote_participants))
    raw = await room.local_participant.perform_rpc(
        destination_identity=identity,
        method=method,
        payload=json.dumps(payload),
        response_timeout=25.0,
    )
    try:
        return json.loads(raw)
    except json.JSONDecodeError as error:
        raise ToolError("The iOS planner returned an unreadable result.") from error


class ResilioPlanner(Agent):
    def __init__(self) -> None:
        super().__init__(instructions=INSTRUCTIONS)

    @function_tool()
    async def planning_turn(self, context: RunContext, message: str) -> dict:
        """Send the user's spoken request to the on-device Resilio planner."""
        return await rpc("planning_turn", {"message": message})

    @function_tool()
    async def select_place(self, context: RunContext, place_index: int) -> dict:
        """Choose a numbered place from the latest snapshot placeCandidates."""
        return await rpc("select_place", {"placeIndex": place_index})

    @function_tool()
    async def choose_alternative(self, context: RunContext, alternative_index: int) -> dict:
        """Choose a safer start time. 0 keeps the original time; 1 is the first alternative."""
        return await rpc("choose_alternative", {"alternativeIndex": alternative_index})

    @function_tool()
    async def save_plan(self, context: RunContext) -> dict:
        """Save the current plan on the user's device after they confirm."""
        return await rpc("save_plan", {})

    @function_tool()
    async def session_snapshot(self, context: RunContext) -> dict:
        """Read the current redacted plan state. Contains no health profile fields."""
        return await rpc("session_snapshot", {})


server = AgentServer()


@server.rtc_session(agent_name="resilio-planner")
async def entrypoint(ctx: JobContext) -> None:
    session = AgentSession(
        vad=silero.VAD.load(),
        stt=openai.STT(),
        llm=openai.LLM(model=os.environ.get("RESILIO_VOICE_LLM", "gpt-4o-mini")),
        tts=openai.TTS(),
    )
    await session.start(agent=ResilioPlanner(), room=ctx.room)
    await session.generate_reply(instructions="Greet briefly and ask what they want to plan. Do not mention health data.")


if __name__ == "__main__":
    cli.run_app(server)
