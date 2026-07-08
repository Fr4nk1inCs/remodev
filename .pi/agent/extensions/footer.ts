/**
 * Custom footer — session metadata in the bottom bar.
 *
 * Shows model (thinking-level), context usage, token counts, CWD,
 * and git branch. Context window is color-coded by fill level.
 */

import type { AssistantMessage } from "@mariozechner/pi-ai";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@mariozechner/pi-tui";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const fmt = (n: number) =>
	n < 1000
		? `${n}`
		: n < 1_000_000
			? `${(n / 1000).toFixed(1)}k`
			: `${(n / 1_000_000).toFixed(1)}M`;

const abbrevCwd = (cwd: string) => {
	const home = process.env.HOME;
	if (home && (cwd === home || cwd.startsWith(home + "/"))) {
		return "~" + cwd.slice(home.length);
	}
	return cwd;
};

type ThemeLike = {
	fg: (color: string, text: string) => string;
	bold: (text: string) => string;
};

const contextColor = (
	pct: number | null,
	thm: ThemeLike,
	s: string,
): string => {
	if (pct === null) return thm.fg("dim", s);
	if (pct >= 90) return thm.fg("error", s);
	if (pct >= 75) return thm.fg("warning", s);
	if (pct >= 50) return thm.fg("muted", s);
	return thm.fg("dim", s);
};

// ---------------------------------------------------------------------------
// Extension
// ---------------------------------------------------------------------------

export default function (pi: ExtensionAPI) {
	let branch: string | undefined;

	pi.on("session_start", (_event, ctx) => {
		ctx.ui.setFooter((tui, thm, footerData) => {
			branch = footerData.getGitBranch() ?? undefined;

			return {
				dispose: footerData.onBranchChange(() => {
					branch = footerData.getGitBranch() ?? undefined;
					tui.requestRender();
				}),

				render(width: number): string[] {
					// --- token totals ------------------------------------------------
					const tokens = { input: 0, output: 0, cacheRead: 0 };
					for (const entry of ctx.sessionManager.getEntries()) {
						if (entry.type !== "message") continue;
						const msg = entry.message;
						if (msg.role === "assistant" && "usage" in msg) {
							const u = (msg as AssistantMessage).usage;
							tokens.input += u.input;
							tokens.output += u.output;
							tokens.cacheRead += u.cacheRead;
						}
					}

					// --- context usage -----------------------------------------------
					const usage = ctx.getContextUsage();
					const pct = usage?.percent ?? null;

					// --- segments ----------------------------------------------------
					const model = ctx.model;
					const modelId = model ? `${model.provider}/${model.id}` : "no model";

					const left = [
						thm.fg("accent", thm.bold(modelId)) +
							" " +
							thm.fg("muted", `(${pi.getThinkingLevel()})`),

						contextColor(
							pct,
							thm,
							// pct is transiently null after compaction while contextWindow
							// is known; rendering "?/200k" is intentional during that window.
							`ctx ${pct !== null ? Math.round(pct) + "%" : "?"}${usage?.contextWindow ? "/" + fmt(usage.contextWindow) : ""}`,
						),

						thm.fg(
							"dim",
							(() => {
								const parts: string[] = [];
								if (tokens.cacheRead > 0)
									parts.push(`↩${fmt(tokens.cacheRead)}`);
								parts.push(`↑${fmt(tokens.input)}`, `↓${fmt(tokens.output)}`);
								return parts.join(" ");
							})(),
						),
					].join(" · ");

					let right = thm.fg("muted", abbrevCwd(ctx.cwd));
					if (branch) right += thm.fg("dim", ` (${branch})`);

					const pad = Math.max(
						1,
						width - visibleWidth(left) - visibleWidth(right),
					);
					return [truncateToWidth(left + " ".repeat(pad) + right, width)];
				},

				invalidate() {},
			};
		});
	});
}
