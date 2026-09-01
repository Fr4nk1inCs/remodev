/**
 * Custom footer — two left-aligned lines:
 *   1. project directory (repo root when inside a worktree) + branch and diff
 *   2. model (thinking level) · context usage · token counts · ttft · tps
 */

import { execFile } from "node:child_process";
import { parse, resolve, sep } from "node:path";
import { promisify } from "node:util";
import type { AssistantMessage } from "@earendil-works/pi-ai";
import type {
	ExtensionAPI,
	ExtensionContext,
	ReadonlyFooterDataProvider,
	SessionEntry,
	Theme,
	ThemeColor,
} from "@earendil-works/pi-coding-agent";
import { type TUI, truncateToWidth } from "@earendil-works/pi-tui";

const execFileAsync = promisify(execFile);

const compactNumber = (n: number): string => {
	if (n < 1000) return `${n}`;
	if (n < 1_000_000) return `${(n / 1000).toFixed(1)}k`;
	return `${(n / 1_000_000).toFixed(1)}M`;
};

const primary = (thm: Theme, text: string): string =>
	thm.fg("accent", thm.bold(text));

const delimiter = (thm: Theme): string => thm.fg("dim", " · ");

const MAX_LEVELS = 3;

class Path {
	readonly raw: string;
	readonly root: string;
	readonly segments: readonly string[];

	private constructor(raw: string, root: string, segments: readonly string[]) {
		this.raw = raw;
		this.root = root;
		this.segments = segments;
	}

	static of(p: string): Path {
		const raw = resolve(p);
		const { root } = parse(raw);
		const segments = raw.slice(root.length).split(sep).filter(Boolean);
		return new Path(raw, root, segments);
	}

	startsWith(other: Path): boolean {
		if (
			this.root !== other.root ||
			other.segments.length > this.segments.length
		)
			return false;
		return other.segments.every((s, i) => this.segments[i] === s);
	}

	/**
	 * `~/a/b/c/d` -> `~/…/c/d`
	 * `/a/b/c/d/e` -> `/…/c/d/e`
	 */
	get display(): string {
		// `~` stands for $HOME and counts as one level
		if (HOME_PATH && this.startsWith(HOME_PATH)) {
			const rest = this.segments.slice(HOME_PATH.segments.length);
			if (rest.length <= MAX_LEVELS - 1) return ["~", ...rest].join(sep);
			return ["~", "…", ...rest.slice(-(MAX_LEVELS - 1))].join(sep);
		}
		if (this.segments.length <= MAX_LEVELS) return this.raw;
		return this.root + ["…", ...this.segments.slice(-MAX_LEVELS)].join(sep);
	}
}

const HOME_PATH = (() => {
	const home = process.env.HOME || process.env.USERPROFILE;
	return home ? Path.of(home) : undefined;
})();

/** Insertions/deletions vs HEAD plus untracked file count. */
class DiffStats {
	readonly added: number;
	readonly removed: number;
	readonly untracked: number;

	constructor(added: number, removed: number, untracked: number) {
		this.added = added;
		this.removed = removed;
		this.untracked = untracked;
	}

	/** `+120 -34 ?2` — `?` counts untracked files. */
	render(): string {
		const parts: string[] = [];
		if (this.added > 0) parts.push(`+${this.added}`);
		if (this.removed > 0) parts.push(`-${this.removed}`);
		if (this.untracked > 0) parts.push(`?${this.untracked}`);
		return parts.join(" ");
	}
}

class GitCommand {
	private readonly cwd: string;

	constructor(dir: Path) {
		this.cwd = dir.raw;
	}

	private async run(...args: string[]): Promise<string> {
		const r = await execFileAsync(
			"git",
			["--no-optional-locks", "-C", this.cwd, ...args],
			{
				encoding: "utf8",
			},
		);
		return r.stdout;
	}

	async repoRoot(): Promise<Path | null> {
		try {
			const out = await this.run("rev-parse", "--show-toplevel");
			return out.trim() ? Path.of(out.trim()) : null;
		} catch {
			return null;
		}
	}

	async diff(): Promise<DiffStats | null> {
		// 1. Unborn HEAD (no commits yet): fall back to the staged-only diff.
		// 2. `diff HEAD` covers staged + unstaged tracked changes.
		const numstat = this.run("diff", "--numstat", "HEAD").catch(() =>
			this.run("diff", "--cached", "--numstat"),
		);
		const porcelain = this.run("status", "--porcelain=v1");
		try {
			const [n, s] = await Promise.all([numstat, porcelain]);
			const d = GitCommand.parseNumstat(n);
			return new DiffStats(d.added, d.removed, GitCommand.countUntracked(s));
		} catch {
			return null;
		}
	}

	private static parseNumstat(out: string): { added: number; removed: number } {
		let added = 0;
		let removed = 0;
		for (const line of out.split("\n")) {
			// Binary files show "-\t-" and are skipped.
			const m = line.match(/^(\d+)\t(\d+)\t/);
			if (!m) continue;
			added += Number(m[1]);
			removed += Number(m[2]);
		}
		return { added, removed };
	}

	private static countUntracked(out: string): number {
		return out.split("\n").filter((line) => line.startsWith("?? ")).length;
	}
}

class GitStatus {
	readonly root: Path;
	readonly command: GitCommand;
	private readonly branch: () => string | null;
	private diff: DiffStats | null = null;

	private lastRefresh = Date.now();
	private inFlight = false;
	private readonly onUpdate: () => void;
	private readonly refreshMs: number;

	private constructor(
		root: Path,
		branch: () => string | null,
		onUpdate: () => void,
		refreshMs: number,
	) {
		this.root = root;
		this.command = new GitCommand(root);
		this.branch = branch;
		this.onUpdate = onUpdate;
		this.refreshMs = refreshMs;
	}

	static async create(
		dir: Path,
		branch: () => string | null,
		onUpdate: () => void,
		refreshMs: number,
	): Promise<GitStatus | null> {
		const root = await new GitCommand(dir).repoRoot();
		if (!root) return null;
		const git = new GitStatus(root, branch, onUpdate, refreshMs);
		git.diff = await git.command.diff();
		return git;
	}

	invalidate(): void {
		this.lastRefresh = 0;
	}

	/** Called from the per-frame render path, so refreshes run in the background. */
	maybeRefresh(): void {
		if (!this.inFlight && Date.now() - this.lastRefresh > this.refreshMs) {
			void this.refreshDiff();
		}
	}

	private async refreshDiff(): Promise<void> {
		if (this.inFlight) return;
		this.inFlight = true;
		try {
			const diff = await this.command.diff();
			if (diff) this.diff = diff;
		} finally {
			this.inFlight = false;
			this.lastRefresh = Date.now();
			this.onUpdate();
		}
	}

	/** Line 1's git suffix: ` (main) · +120 -34 ?2`. */
	render(thm: Theme): string {
		const branch = this.branch();
		if (!branch) return "";
		const diff = this.diff?.render();
		return (
			thm.fg("dim", ` (${branch})`) +
			(diff ? delimiter(thm) + thm.fg("dim", diff) : "")
		);
	}
}

class Project {
	private path: Path;
	private git: GitStatus | null = null;

	constructor(
		cwd: string,
		branch: () => string | null,
		onUpdate: () => void,
		refreshMs = 2000,
	) {
		// cwd is fixed for a session's lifetime, so repo detection runs once here
		// and is never re-polled.
		this.path = Path.of(cwd);
		void this.detect(branch, onUpdate, refreshMs);
	}

	invalidate(): void {
		this.git?.invalidate();
	}

	maybeRefresh(): void {
		this.git?.maybeRefresh();
	}

	render(thm: Theme): string {
		return primary(thm, this.path.display) + (this.git?.render(thm) ?? "");
	}

	private async detect(
		branch: () => string | null,
		onUpdate: () => void,
		refreshMs: number,
	): Promise<void> {
		this.git = await GitStatus.create(this.path, branch, onUpdate, refreshMs);
		if (this.git) this.path = this.git.root;
		onUpdate();
	}
}

type TokenTotals = { input: number; output: number; cacheRead: number };

/** Reference: pi's estimateTokens heuristic (chars/4), used by compaction. */
const CHARS_PER_TOKEN = 4;

const WINDOW_MS = 3000;

class StreamMetrics {
	private requestedAt: number | null = null;
	private startedAt: number | null = null;
	// Usage only arrives in the final chunk, so mid-stream we count chars.
	private samples: { at: number; chars: number }[] = [];
	private totalChars = 0;
	private lastTtft: number | null = null;
	private lastTps: number | null = null;

	start(): void {
		this.requestedAt = Date.now();
		this.startedAt = null;
		this.samples = [];
		this.totalChars = 0;
	}

	update(delta: string): void {
		const now = Date.now();
		if (this.startedAt === null) {
			this.startedAt = now;
			// ttft: provider request (before_provider_request) to first delta.
			if (this.requestedAt !== null)
				this.lastTtft = (now - this.requestedAt) / 1000;
		}
		this.samples.push({ at: now, chars: delta.length });
		this.totalChars += delta.length;
	}

	end(outputTokens?: number): void {
		this.requestedAt = null;
		if (this.startedAt === null) return;
		const seconds = (Date.now() - this.startedAt) / 1000;
		const tokens = outputTokens || Math.ceil(this.totalChars / CHARS_PER_TOKEN);
		if (seconds > 0) this.lastTps = tokens / seconds;
		this.startedAt = null;
	}

	render(thm: Theme): string {
		const parts: string[] = [];
		if (this.lastTtft !== null) parts.push(`${this.lastTtft.toFixed(1)}s`);
		if (this.startedAt === null) {
			if (this.lastTps !== null) parts.push(`${this.lastTps.toFixed(1)} tps`);
		} else {
			const now = Date.now();
			const cutoff = now - WINDOW_MS;
			while (this.samples.length > 0 && this.samples[0].at < cutoff)
				this.samples.shift();
			const chars = this.samples.reduce((sum, s) => sum + s.chars, 0);
			// A minimum window damps the spike right after the first delta.
			const seconds = Math.max(
				Math.min(now - this.startedAt, WINDOW_MS) / 1000,
				0.5,
			);
			// `~` marks an estimate.
			parts.push(`~${(chars / CHARS_PER_TOKEN / seconds).toFixed(1)} tps`);
		}
		return parts.length > 0 ? thm.fg("dim", parts.join(" ")) : "";
	}
}

class SessionStatus {
	private readonly ctx: ExtensionContext;
	private readonly pi: ExtensionAPI;
	private readonly metrics: StreamMetrics;

	constructor(ctx: ExtensionContext, pi: ExtensionAPI, metrics: StreamMetrics) {
		this.ctx = ctx;
		this.pi = pi;
		this.metrics = metrics;
	}

	render(thm: Theme): string {
		return [
			this.renderModel(thm),
			this.renderContext(thm),
			this.renderTokens(thm),
			this.metrics.render(thm),
		]
			.filter((s) => s !== "")
			.join(delimiter(thm));
	}

	/** `provider/model (high)` */
	private renderModel(thm: Theme): string {
		const model = this.ctx.model;
		const modelId = model ? `${model.provider}/${model.id}` : "no model";
		const thinking = model?.reasoning
			? ` ${thm.fg("muted", `(${this.pi.getThinkingLevel()})`)}`
			: "";
		return primary(thm, modelId) + thinking;
	}

	/** `ctx 42%/262.1k`
	 * `?` while tokens are unknown (transient after compaction). */
	private renderContext(thm: Theme): string {
		const usage = this.ctx.getContextUsage();
		const pct = usage?.percent ?? null;
		const contextWindow = usage?.contextWindow ?? this.ctx.model?.contextWindow;
		const pctText = pct !== null ? `${Math.round(pct)}%` : "?";
		const windowText = contextWindow ? `/${compactNumber(contextWindow)}` : "";
		return thm.fg(this.contextColor(pct), `ctx ${pctText}${windowText}`);
	}

	private contextColor(pct: number | null): ThemeColor {
		if (pct === null) return "dim";
		if (pct >= 90) return "error";
		if (pct >= 75) return "warning";
		if (pct >= 50) return "muted";
		return "dim";
	}

	/** `↩1.0k ↑500 ↓2.0k` */
	private renderTokens(thm: Theme): string {
		const tokens = SessionStatus.sumTokenUsage(
			this.ctx.sessionManager.getEntries(),
		);
		const parts: string[] = [];
		if (tokens.cacheRead > 0) parts.push(`↩${compactNumber(tokens.cacheRead)}`);
		parts.push(
			`↑${compactNumber(tokens.input)}`,
			`↓${compactNumber(tokens.output)}`,
		);
		return thm.fg("dim", parts.join(" "));
	}

	/** toolResult (e.g. subagent calls) and compaction/branch_summary entries (the summary call) also carry usage. */
	private static entryUsage(entry: SessionEntry): TokenTotals | null {
		if (entry.type === "message") {
			const msg = entry.message;
			if (msg.role === "assistant" && "usage" in msg)
				return (msg as AssistantMessage).usage;
			if (msg.role === "toolResult" && msg.usage) return msg.usage;
			return null;
		}
		if (
			(entry.type === "branch_summary" || entry.type === "compaction") &&
			entry.usage
		) {
			return entry.usage;
		}
		return null;
	}

	/** Reference: pi's core/usage-totals.ts (not in the package's exports map) */
	private static sumTokenUsage(entries: SessionEntry[]): TokenTotals {
		const totals: TokenTotals = { input: 0, output: 0, cacheRead: 0 };
		for (const entry of entries) {
			const u = SessionStatus.entryUsage(entry);
			if (u) {
				totals.input += u.input;
				totals.output += u.output;
				totals.cacheRead += u.cacheRead;
			}
		}
		return totals;
	}
}

class Footer {
	private readonly thm: Theme;
	private readonly unsubscribeBranch: () => void;
	private readonly project: Project;
	private readonly session: SessionStatus;

	constructor(
		ctx: ExtensionContext,
		pi: ExtensionAPI,
		tui: TUI,
		thm: Theme,
		footerData: ReadonlyFooterDataProvider,
		metrics: StreamMetrics,
	) {
		this.thm = thm;
		const branch = () => footerData.getGitBranch();
		this.project = new Project(ctx.cwd, branch, () => tui.requestRender());
		this.session = new SessionStatus(ctx, pi, metrics);
		this.unsubscribeBranch = footerData.onBranchChange(() =>
			tui.requestRender(),
		);
	}

	dispose = (): void => {
		this.unsubscribeBranch();
	};

	invalidate = (): void => {
		this.project.invalidate();
	};

	render = (width: number): string[] => {
		this.project.maybeRefresh();

		const ellipsis = this.thm.fg("dim", "…");
		return [
			truncateToWidth(this.project.render(this.thm), width, ellipsis),
			truncateToWidth(this.session.render(this.thm), width, ellipsis),
		];
	};
}

export default function (pi: ExtensionAPI) {
	// The extension factory re-runs per session runtime, so these handlers and
	// the tracker never leak across /new or /resume.
	const metrics = new StreamMetrics();
	// before_provider_request fires when the request is sent.
	pi.on("before_provider_request", () => metrics.start());
	pi.on("message_update", (e) => {
		const ev = e.assistantMessageEvent;
		// All delta events (text / thinking / toolcall) carry `delta`.
		if (e.message.role === "assistant" && "delta" in ev)
			metrics.update(ev.delta);
	});
	pi.on("message_end", (e) => {
		if (e.message.role === "assistant") {
			metrics.end((e.message as AssistantMessage).usage?.output);
		}
	});
	pi.on("session_start", (_event, ctx) => {
		ctx.ui.setFooter(
			(tui, thm, footerData) =>
				new Footer(ctx, pi, tui, thm, footerData, metrics),
		);
	});
}
