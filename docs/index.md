---
layout: page
title: "I gave my terminal an undo button for rm — and taught it to speak human"
description: >-
  shellish is a free, open-source AI terminal helper for zsh, bash, and
  PowerShell. Type a sentence in any language and it runs the right shell
  command, corrects your typos, and sends every rm to the trash. A
  stays-out-of-your-way, open-source alternative to AI terminals like Warp,
  using the Claude or Codex CLI you already have.
image: /demo.gif
---

*A free, open-source AI terminal helper that runs inside the shell you already have. It turns a sentence — in any language — into the right command, catches your typos, and sends every `rm` to the trash instead of the void. Here's how a thirty-line hack turned into a lesson about shells, LLMs, and the gap between a clever idea and a safe one.*

🐦 [Follow along on X](https://x.com/xixian42/status/2066172763577143498?s=20) · 💻 [Source on GitHub](https://github.com/XiXian42/shellish) (MIT)

![shellish demo]({{ "/demo.gif" | relative_url }})

```
curl -fsSL https://raw.githubusercontent.com/XiXian42/shellish/main/install.sh | bash
```

---

## The itch

I've been using a terminal every day for years, and I still can't remember the flags for `tar`. Or `find`. Or how to make `xargs` do the thing with the null separator. I know *what* I want — "extract this archive," "find every PNG bigger than a megabyte," "which process is sitting on port 8080" — I just can't always remember the exact incantation.

So I'd do what everyone does now: alt-tab to a chat window, type the question in English, copy the command back, paste it, run it. It works. But it's a tiny tax I paid a dozen times a day, and every alt-tab pulled me out of the place I was actually working: the shell.

There are full **AI terminals** — Warp and friends — that solve this by replacing your terminal. They're slick. But I didn't want to switch terminals, and when I went looking for a *free, open-source Warp alternative* that didn't make me move, I mostly found more terminals to install. I like my `zsh`. I like my prompt, my aliases, my muscle memory. I just wanted to type a sentence *in the shell I already have* and have something sensible happen — ideally using the AI CLI I'd already set up, rather than yet another account.

That was the whole idea: **keep the shell, add a fallback that speaks human.** Not English specifically — human. The request goes to a language model, so whatever language *it* understands, the shell now understands too. I type English most of the time, but `删除这个目录下所有的 .venv` works exactly as well, and so does Japanese, or German, or a sloppy mix of two languages in one line. There's no language setting because there's no language logic — it's just passed through to the model verbatim.

---

## The "aha": the shell already has a hook for this

Here's the thing I'd never thought about until I needed it. When you type a command your shell doesn't recognize, it doesn't just give up — it calls a function. In `zsh` it's `command_not_found_handler`. In `bash` it's `command_not_found_handle`. Linux distros use this to say "the program `htop` isn't installed, try `apt install htop`."

That hook is the perfect place to put a fallback. The logic almost writes itself:

- You type `git status` → it's a real command → runs normally, the hook never fires.
- You type `shrink every png in this folder` → no command called `shrink` → the hook fires → hand the whole line to an AI.

No prefix to remember. No separate mode. You just type. If it's a command, it's a command. If it's a sentence, it quietly becomes one.

```
$ shrink every png in this folder

  🤖 pi ← shrink every png in this folder
  ⚙  bash  for f in *.png; do sips -Z 1200 "$f" --out "$f"; done
  ✓  done
```

The first version was about thirty lines of shell. It felt like magic for an afternoon.

---

## Decision one: don't ship a brain — reuse the AI you already run in the terminal

The obvious next question is "which AI does it use?" My answer was: none of mine.

A lot of people have already figured out how to use Claude or Codex in the terminal — they've installed Claude Code, OpenAI's Codex CLI, or a similar coding agent. Those tools are *good*. They can read files, run commands, look at the output, and try again. Rebuilding that loop would be foolish and worse.

So shellish doesn't have a model, an API key, or a server. It's a dispatcher. It finds whichever agent you've already got, builds a prompt, hands the request over, and gets out of the way. If you've authenticated Claude Code, that's what runs. The tool is maybe a few hundred lines of glue around software you already trust.

This also sidesteps the most boring problem in this whole space — billing, keys, rate limits — by simply not having it.

---

## Decision two: catch the typos, for free

Once the hook was working, an obvious adjacent problem appeared. When you fat-finger `gti status`, the shell *also* can't find `gti`, so the hook fires for that too. I didn't want to send a typo to an AI and have it confidently run a "fixed" command I didn't actually ask for.

The naive design is two AI calls: first ask "is this a typo or a real request?", then act. That's slow and it doubles the cost.

The trick I landed on is to do it in **one** call. When the request comes from the shell hook, I prepend a small instruction to the prompt that says, roughly:

> Before anything else, classify this. If it looks like a *mistyped command* (`gti status`, `pyhton3 app.py`), reply with exactly one line — `__TYPO__: <the correction>` — and stop. Don't run anything. Otherwise, treat it as a real request and handle it normally.

Then the renderer watches the very first bytes of the model's reply. If they start with `__TYPO__:`, it prints a gentle suggestion and exits without doing anything. Otherwise it streams the answer like normal.

```
$ gti status
  did you mean:  git status
```

One model call. The typo never runs. And because it's the *same* call that would have handled a real request, there's no extra latency for the common case.

---

## Decision three: make `rm` undo-able

This is the part I feel strongest about, and it's where the project stopped being a toy.

There's a reason "*how to undo an `rm` command*" is a perennial search on Linux, Mac, and Windows alike: the plain answer is *you mostly can't*. If you let an AI run shell commands, sooner or later it's going to run `rm`. Maybe it's right. Maybe it misread your request. Maybe it globbed something wider than you meant. On a normal shell, `rm -rf` is final. There's no trash can, no undo.

So shellish quietly reroutes deletion. Before launching the agent, it puts a fake `rm` (and `del`, `rmdir`, etc.) earlier on the `PATH` than the real one. When the agent runs `rm something`, it actually hits my script, which:

1. pauses and tells the parent process "the agent wants to delete X",
2. the parent shows *you* a prompt — allow once, allow all this session, or deny,
3. and if you allow, it moves the target to the system trash (the `trash` CLI on macOS, the freedesktop trash spec on Linux, the Recycle Bin on Windows) instead of destroying it.

```
$ delete the build directory

  ⚠️  rm -rf build
  → will move to trash, not permanently delete

  [y] allow once   [a] allow all (this session)   [N] deny
```

Delete the wrong thing? It's in the trash. You can get it back. That one guarantee changed how comfortable I was letting the thing run at all.

(The cross-process handshake — fake `rm` and the parent talking through little temp files — is the single fiddliest piece of code in the project, and the part I've rewritten the most. More on why below.)

---

## Decision four: one face for four brains

Because shellish doesn't ship a model, it has to drive whatever agent you already have — `pi`, `omp`, Claude Code, or Codex. And here's the annoying part: they all stream their progress as JSON, and **every one uses a different shape.**

Same four ideas in every case — "I'm thinking," "I'm running this command," "here's the output," "here's my answer" — but four different vocabularies:

- Claude emits `stream_event` objects with `content_block_delta` chunks.
- Codex emits `item.started` / `item.completed` wrapping `command_execution` items.
- pi and omp emit `message_update` with `text_delta` events.

If I exposed those differences, the tool would feel like four different tools. So there's a small renderer whose entire job is to flatten all of them into one calm view: a spinner while the agent thinks, a `⚙` line when it runs a command, the output folded down to a one-line summary, and the final answer streamed out character by character. You genuinely can't tell which agent is behind the curtain — and that's the point. You pick the brain; shellish owns the face.

This sounds trivial and absolutely was not. Streaming terminal UIs are a swamp of small correctness bugs: a spinner that leaves garbage on screen when its line is wider than the window; CJK characters that occupy two columns and quietly break every width calculation; a single JSON message split across two reads so both halves fail to parse and a chunk of the answer vanishes from history. None of it is hard in isolation. All of it has to be right at once, or the illusion of "one clean tool" falls apart.

---

## How a request actually flows

Put together, one line of natural language travels like this:

```
you type a sentence at the prompt
        ↓
command_not_found_handler  (zsh / bash)
        ↓
shellish --from-shell "<your sentence>"
        ↓
build a prompt: house rules + the typo gate + your memory
               + recent history in this dir + the current time
        ↓
spawn your agent (Claude Code / Codex / pi …) with a fake `rm` on PATH
        ↓
stream the agent's output, rendered into something readable
        ↓
save a short record to history
```

A couple of small things in there earn their keep:

- **Memory.** If you say "remember I'm in London and I use neovim," the agent writes that to a little `memory.md`, and it's quietly included in future prompts. So later, "what time is it for my team" or "open this in my editor" just works.
- **Per-directory history.** The last few exchanges *in the current directory* get fed back in, so follow-ups like "now do the same for the jpgs" have context — without dragging your entire shell history into every prompt.

---

## Then I tried to make it work on Windows

This is where I'll be honest: the Unix version took a weekend, and Windows took *much* longer. If you've only ever shipped for macOS and Linux, Windows is a great teacher of humility. A sampler of what bit me:

- **PowerShell doesn't use `PATH` for `rm`.** On Unix, putting a fake `rm` earlier in `PATH` is enough. In PowerShell, `rm` is an *alias* for the `Remove-Item` cmdlet, resolved by the language itself — it never looks at `PATH`. So the whole "intercept deletion" trick silently did nothing. The fix was to wrap `Remove-Item` (and rebind the aliases) inside the PowerShell profile, which is its own small adventure in not breaking `-WhatIf` and scripts that opt out.

- **Line endings.** A user reported `shellish.cmd` just *hanging*. The cause: the `.cmd` files were committed with Unix line endings (LF), GitHub's zip download served those bytes as-is, and `cmd.exe`'s ancient parser mis-scans LF-only batch files and stalls. The fix is a one-line `.gitattributes` rule forcing `*.cmd` to CRLF — but finding it meant reproducing a Windows-only hang from a Mac.

- **Where is "Documents," really?** The installer writes a PowerShell profile. On a machine with OneDrive folder redirection, `%USERPROFILE%\Documents` isn't where PowerShell actually reads your profile from, and it may be read-only. You have to ask the OS for the *real* Documents path.

None of these are deep. They're just the kind of papercuts you only discover by running on the actual platform, with real users, on machines configured in ways you'd never think to test. Windows is still labelled beta for a reason.

---

## The problems I haven't solved (and one I decided not to)

I want to be straight about the rough edges, because they're the interesting part.

### 1. There is no sandbox.

This is the big one. To make the agent run smoothly without nagging you for permission on every single step, shellish launches it with its safety prompts turned off (`--dangerously-skip-permissions` for Claude Code, the equivalent for Codex). That means: **deletion is the only thing with a guardrail.** Everything else — writing files, `curl … | bash`, a force-push, `sudo` — runs without an extra confirmation.

I think that's a reasonable trade-off for "a coding agent you'd already trust, in a directory you trust," and the README says so in plain language. But it is absolutely not a safe-by-default sandbox, and pretending otherwise would be dishonest. If you need hard isolation, you should use your agent directly with its own approval flow.

### 2. The "half-command, half-sentence" blind spot.

Remember the elegant trick — the hook fires only when the first word *isn't* a real command? That elegance is also a hole. If you type:

```
$ find all png files larger than 1mb
```

…then `find` *is* a real command. The shell runs it, gets confused by "all png files" as arguments, and errors out. The hook never fires, because as far as the shell is concerned you ran a perfectly real program (badly).

I went down the rabbit hole on this. Every fix trades one annoyance for another:

- *Ask an LLM to classify every line first?* Now every `ls` pays for a model round-trip.
- *Send anything with 3+ words to the AI?* Now `git push origin main` goes to the AI. No thanks.
- *Keep a blacklist of confusing commands like `find`/`grep`/`sed`?* Endless maintenance, and it leaks.
- *Run the command, and fall back to the AI if it fails?* Double the noise and a stderr mess every time.

I wrote them all down, weighed them, and decided **not to fix it.** The current behavior — fast for real commands, AI for genuine sentences, with this one known gap — is the best trade-off I found. The workaround is to wrap it in quotes (`"find all png files…"`) or call `shellish "…"` explicitly. Sometimes the right engineering decision is to document a limitation instead of papering over it with something worse.

### 3. Your words leave your machine.

Every request sends the model your prompt, your current directory, a little recent history, and your memory file. That's inherent to the whole premise — it's an AI tool — but it's worth saying out loud. Where that data goes is governed by whichever agent you configured. shellish itself has no server and stores nothing remotely, but it's not magic privacy either.

---

## "So is this a free Warp alternative?"

Sort of — and it's worth being precise, because it's the question I'd ask.

If what you want from an AI terminal is *the slick all-in-one app* — blocks, autocomplete, a built-in editor, a polished GUI — shellish is **not** that, and Warp does it better. If what you want is the **one feature** that sent you searching for a "Warp alternative" in the first place — *type a sentence, get the command* — without adopting a new terminal, a new shell, or a new subscription, then yes: shellish is the free, open-source, MIT-licensed, stays-out-of-your-way version of exactly that. It runs in zsh, bash, or PowerShell, and it borrows the AI you already pay for instead of selling you another.

It's a small tool with a narrow job, not a platform. That's the whole pitch.

---

## What I actually learned

The idea was a one-liner: "use a sentence in the shell." The implementation taught me that almost all the work is in the seams — the typo that shouldn't run, the delete that should be reversible, the platform that resolves `rm` differently, the line ending that hangs a parser.

The clever part (hooking `command_not_found`) took an afternoon. The *honest* part — making it safe enough to recommend, and being upfront about where it isn't — took everything after that. I think that ratio is true of a lot of small tools. The demo is easy. The edges are the product.

If you want to try it, it's open source, MIT, one line to install, and it uses whatever agent you've already got — speaking whatever language you think in. Just go in knowing exactly what it is: a thin, convenient, *unsandboxed* bridge between the sentence in your head and the shell in front of you.

And maybe keep it out of directories you can't afford to lose. The trash can only saves you from `rm`.

```
curl -fsSL https://raw.githubusercontent.com/XiXian42/shellish/main/install.sh | bash
```

**Links:** [GitHub repo](https://github.com/XiXian42/shellish) · [the X thread](https://x.com/xixian42/status/2066172763577143498?s=20). If you try it — especially on Windows — I'd genuinely like the bug reports.
