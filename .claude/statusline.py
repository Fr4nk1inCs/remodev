# /// script
# requires-python = ">=3.13"
# dependencies = [ "pydantic>=2" ]
# ///

from __future__ import annotations

import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from pathlib import Path
from typing import Annotated, Literal

from pydantic import (
    UUID4,
    BaseModel,
    ConfigDict,
    Field,
    TypeAdapter,
    ValidationError,
)


class IgnoreModel(BaseModel):
    model_config = ConfigDict(extra="ignore")


class Model(IgnoreModel):
    id: str
    display_name: str


class Workspace(IgnoreModel):
    current_dir: Path


class EffortLevel(StrEnum):
    OFF = "off"  # Nonexistent effort level in schema (to replace None)
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    XHIGH = "xhigh"
    MAX = "max"


class Effort(IgnoreModel):
    level: EffortLevel = Field(default=EffortLevel.OFF)


class ContextWindow(IgnoreModel):
    context_window_size: int
    used_percentage: float | None


class StatuslineInput(IgnoreModel):
    cwd: Path
    transcript_path: Path
    workspace: Workspace
    model: Model
    context_window: ContextWindow | None = None
    effort: Effort = Field(default_factory=Effort)


# Rendering ====================================================================


class Theme(StrEnum):
    RESET = "\033[0m"
    ACCENT = "\033[1;36m"  # Bold Cyan
    DIM = "\033[2m"
    WARNING = "\033[33m"
    ERROR = "\033[31m"

    def paint(self, text: str) -> str:
        return f"{self.value}{text}{Theme.RESET.value}"


@dataclass(frozen=True)
class Render:
    int_precision: int = 1
    max_path_levels: int = 3

    def integer(self, n: int) -> str:
        if n < 1000:
            return str(n)
        elif n < 1_000_000:
            return f"{n / 1_000:.{self.int_precision}f}K"
        else:
            return f"{n / 1_000_000:.{self.int_precision}f}M"

    def path(self, path: Path) -> str:
        path = path.resolve()

        if path.is_relative_to(HOME):
            parts = path.relative_to(HOME).parts
            sublevel = self.max_path_levels - 1
            if len(parts) <= sublevel:
                return str(Path("~", *parts))
            return str(Path("~", "…", *parts[-sublevel:]))

        parts = path.parts[1:]
        if len(parts) <= self.max_path_levels:
            return str(path)
        return str(Path(path.anchor, "…", *parts[-self.max_path_levels :]))

    def percentage(self, value: float | None) -> str:
        if value is None:
            return Theme.DIM.paint("?")
        theme = Theme.DIM
        if value >= 90:
            theme = Theme.ERROR
        elif value >= 75:
            theme = Theme.WARNING
        return theme.paint(f"{round(value)}%")


HOME = Path.home()
DELIMITER = Theme.DIM.paint(" · ")
RENDER = Render(int_precision=1, max_path_levels=3)


# Project Stats ================================================================


@dataclass(frozen=True)
class DiffStats:
    added: int = 0
    removed: int = 0
    untracked: int = 0

    def __bool__(self) -> bool:
        return any((self.added > 0, self.removed > 0, self.untracked > 0))

    def render(self):
        parts = []
        if self.added > 0:
            parts.append("+" + str(self.added))
        if self.removed > 0:
            parts.append("-" + str(self.removed))
        if self.untracked > 0:
            parts.append("?" + str(self.untracked))
        return " ".join(parts)


class GitError(Exception):
    pass


class GitCmd:
    def __init__(self, cwd: Path):
        self.cwd = cwd

    def run(self, *args: str) -> str:
        try:
            result = subprocess.run(
                [
                    "git",
                    "--no-optional-locks",
                    "-C",
                    str(self.cwd),
                    *args,
                ],
                capture_output=True,
                text=True,
                timeout=5,
                check=True,
            )
        except (OSError, subprocess.CalledProcessError) as e:
            raise GitError(f"Git command failed: {e}") from e
        return result.stdout.strip()

    def root(self) -> Path | None:
        try:
            output = self.run("rev-parse", "--show-toplevel")
            return Path(output)
        except GitError:
            return None

    def branch(self) -> str | None:
        for args in (
            ("symbolic-ref", "--short", "-q", "HEAD"),
            ("rev-parse", "--short", "HEAD"),
        ):
            try:
                return self.run(*args) or None
            except GitError:
                continue
        return None

    def diff(self) -> DiffStats | None:
        try:
            try:
                numstat = self.run("diff", "--numstat", "HEAD")
            except GitError:
                numstat = self.run("diff", "--cached", "--numstat")
            porcelain = self.run("status", "--porcelain=v1")
        except GitError:
            return None

        added, removed = self._parse_numstat(numstat)
        untracked = sum(line.startswith("??") for line in porcelain.splitlines())

        return DiffStats(added=added, removed=removed, untracked=untracked)

    @staticmethod
    def _parse_numstat(numstat: str) -> tuple[int, int]:
        added = removed = 0
        for line in numstat.splitlines():
            plus, minus, *_ = line.split("\t") + ["", ""]
            added += int(plus) if plus.isdigit() else 0
            removed += int(minus) if minus.isdigit() else 0
        return added, removed


class ProjectStats:
    def __init__(self, cwd: Path):
        self.cwd = cwd
        self.git = GitCmd(cwd)

    def render(self) -> str:
        line = Theme.ACCENT.paint(RENDER.path(self.cwd))

        root = self.git.root()
        if root is None:
            return line
        line = Theme.ACCENT.paint(RENDER.path(root))

        branch = self.git.branch()
        if branch is not None:
            line += Theme.DIM.paint(f" ({branch})")

        diff = self.git.diff()
        if diff:
            line += DELIMITER + Theme.DIM.paint(diff.render())

        return line


# Session Stats ================================================================


class TokenUsage(IgnoreModel):
    input: int = Field(default=0, alias="input_tokens")
    output: int = Field(default=0, alias="output_tokens")
    cache_read: int = Field(default=0, alias="cache_read_input_tokens")
    cache_write: int = Field(default=0, alias="cache_creation_input_tokens")

    def __add__(self, other: TokenUsage) -> TokenUsage:
        return TokenUsage(
            input_tokens=self.input + other.input,
            output_tokens=self.output + other.output,
            cache_read_input_tokens=self.cache_read + other.cache_read,
            cache_creation_input_tokens=self.cache_write + other.cache_write,
        )

    def __sub__(self, other: TokenUsage) -> TokenUsage:
        return TokenUsage(
            input_tokens=self.input - other.input,
            output_tokens=self.output - other.output,
            cache_read_input_tokens=self.cache_read - other.cache_read,
            cache_creation_input_tokens=self.cache_write - other.cache_write,
        )

    def __bool__(self) -> bool:
        return any(
            (
                self.input > 0,
                self.output > 0,
                self.cache_read > 0,
                self.cache_write > 0,
            )
        )

    def render(self) -> str:
        parts = []
        if self.cache_read > 0:
            parts.append(f"r{RENDER.integer(self.cache_read)}")
        if self.cache_write > 0:
            parts.append(f"w{RENDER.integer(self.cache_write)}")
        parts += [
            f"i{RENDER.integer(self.input)}",
            f"o{RENDER.integer(self.output)}",
        ]
        return " ".join(parts)


class ApiRequest(IgnoreModel):
    type: Literal["api-request"]
    id: UUID4
    timestamp: datetime


class Message(IgnoreModel):
    usage: TokenUsage


class AssistantMessage(IgnoreModel):
    type: Literal["assistant"]
    isSidechain: bool
    requestRef: UUID4
    message: Message
    timestamp: datetime


TranscriptEntry = Annotated[
    AssistantMessage | ApiRequest,
    Field(discriminator="type"),
]

TranscriptEntryAdapter: TypeAdapter[AssistantMessage | ApiRequest] = TypeAdapter(
    TranscriptEntry
)


@dataclass(frozen=True)
class MessageTps:
    duration: float
    output: int

    @property
    def tps(self) -> float:
        return self.output / self.duration if self.duration > 0 else 0.0

    def render(self) -> str:
        return f"{self.tps:.1f}t/s"


class TranscriptParser:
    def __init__(self, transcript: Path):
        self.path = transcript

    def __iter__(self):
        try:
            f = self.path.open(encoding="utf-8", errors="replace")
        except OSError:
            # Transcript not written yet (or deleted) — no entries.
            return
        with f:
            for line in f:
                try:
                    entry = TranscriptEntryAdapter.validate_json(line)
                    yield entry
                except ValidationError:
                    continue

    def parse(self) -> tuple[TokenUsage, MessageTps | None]:
        usage = TokenUsage()
        req_timing: dict[UUID4, datetime] = {}
        last_message: AssistantMessage | None = None
        seen: dict[UUID4, AssistantMessage] = {}

        for entry in self:
            if isinstance(entry, ApiRequest):
                req_timing[entry.id] = entry.timestamp
                continue

            if (prev := seen.get(entry.requestRef)) is not None:
                usage -= prev.message.usage
            usage += entry.message.usage

            seen[entry.requestRef] = entry

            if not entry.isSidechain:
                last_message = entry

        if last_message is None:
            return usage, None

        requested = req_timing.get(last_message.requestRef)
        if requested is None:
            return usage, None

        duration = (last_message.timestamp - requested).total_seconds()
        output = last_message.message.usage.output
        if duration <= 0 or output <= 0:
            return usage, None
        return usage, MessageTps(duration=duration, output=output)


class SessionStats:
    def __init__(self, data: StatuslineInput):
        self.model = data.model.display_name
        self.effort = data.effort.level
        window = data.context_window
        self.context_window_size = window.context_window_size if window else None
        self.context_used_percentage = window.used_percentage if window else None
        self.usage, self.tps = TranscriptParser(data.transcript_path).parse()

    def render(self) -> str:
        return DELIMITER.join(
            part
            for part in (
                self.render_model(),
                self.render_context(),
                Theme.DIM.paint(self.usage.render()) if self.usage else "",
                Theme.DIM.paint(self.tps.render()) if self.tps is not None else "",
            )
            if part
        )

    def render_model(self) -> str:
        name = Theme.ACCENT.paint(self.model)
        if self.effort is EffortLevel.OFF:
            return name
        return name + Theme.DIM.paint(f" ({self.effort})")

    def render_context(self) -> str:
        pct = RENDER.percentage(self.context_used_percentage)
        if self.context_window_size is None:
            return pct
        size = Theme.DIM.paint("/" + RENDER.integer(self.context_window_size))
        return f"{pct}{size}"


if __name__ == "__main__":
    data = StatuslineInput.model_validate_json(sys.stdin.read())
    # pyrefly: ignore [missing-attribute]
    sys.stdout.reconfigure(encoding="utf-8")
    print(ProjectStats(data.cwd).render())
    print(SessionStats(data).render())
