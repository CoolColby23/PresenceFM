# OpenAI Build Week final submission

Deadline: **Tuesday, July 21, 2026 at 5:00 PM Pacific Time**.

This archived page records the public submission process used for the project.
Personal declarations, account access, and session identifiers are intentionally
not included in the repository.

## Already prepared

- Public MIT-licensed repository: <https://github.com/CoolColby23/PresenceFM>
- Devpost project: <https://devpost.com/software/presence-fm>
- Category: **Apps for Your Life**
- Credential-free judge command: `swift run PresenceFM --demo`
- Demo safety gates that block Discord and Last.fm publishing
- Automated Build Week verification: `./scripts/verify-build-week.sh`
- Under-three-minute narration and screen plan:
  [BUILD-WEEK-DEMO-SCRIPT.md](BUILD-WEEK-DEMO-SCRIPT.md)
- Project description, technology list, repository link, website link, and
  thumbnail on Devpost

## Submission steps used

Complete these in order. When steps 1–4 are finished, send the four requested
items listed under **Return to Codex** so Codex can populate and submit the final
Devpost form.

### 1. Review the project description in your own voice

1. Open <https://devpost.com/software/presence-fm>.
2. Sign in to the Devpost account that owns the project.
3. Choose **Manage project** or **Edit project**.
4. Read the tagline and full description aloud.
5. Rewrite any sentence you would not naturally say. Devpost specifically asks
   entrants not to submit an AI-generated description unchanged.
6. Save the project.
7. Open the public project page once and confirm the formatting and links work.

Do not remove the judge quickstart, the Codex/GPT-5.6 explanation, or the
local-first privacy explanation.

### 2. Record and publish the demo video

Prepare the app before recording:

1. Open Terminal.
2. Run:

   ```sh
   cd /path/to/PresenceFM
   swift run PresenceFM --demo
   ```

3. Let Demo Mode complete at least two sample tracks so **Listening History**
   has content.
4. Arrange the PresenceFM window, repository, and Terminal so no private
   notification, credential, username, or unrelated listening history is shown.

Record on macOS:

1. Press **Shift-Command-5**.
2. Choose **Record Entire Screen** or **Record Selected Portion**.
3. Open **Options** and select the microphone you will narrate with.
4. Follow [BUILD-WEEK-DEMO-SCRIPT.md](BUILD-WEEK-DEMO-SCRIPT.md).
5. Stop recording from the menu-bar stop button.
6. Trim out build waits, permission prompts, mistakes, and dead time.
7. Confirm the final file is under **3:00**, includes voiceover, and audibly says
   both **Codex** and **GPT-5.6** while explaining their concrete contribution.

Publish:

1. Sign in to YouTube and choose **Create → Upload video**.
2. Use a clear title such as `PresenceFM — OpenAI Build Week Demo`.
3. Set visibility to **Public**. Do not leave it Private, Draft, or Scheduled.
4. Finish the upload and wait for processing.
5. Open the public URL in a private/incognito browser window.
6. Confirm it plays without signing in, is under three minutes, and has audible
   narration.
7. Copy the final `youtube.com/watch` or `youtu.be` URL.

### 3. Retrieve the Codex Session ID

1. Open the primary Codex task where most of PresenceFM's core Build Week work
   happened.
2. Enter `/feedback`.
3. Copy the Session ID shown by Codex.
4. Keep the full ID exactly as displayed; do not shorten or reformat it.

If this task is the primary build task, run `/feedback` here.

### 4. Confirm the personal submission fields

Write down:

1. **Submitter Type:** `Individual`, `Team of Individuals`, or `Organization`.
2. **Country of Residence:** the country Devpost should associate with the
   entrant.

These are personal declarations and should not be inferred from the repository.

### 5. Return to Codex for final submission

Send one message containing:

```text
Video URL: …
Submitter Type: …
Country of Residence: …
Codex Session ID: …
I reviewed the Devpost description in my own voice: yes
Submit the final Devpost entry: yes
```

Codex can then fill:

- Category: `Apps for Your Life`
- Repository: `https://github.com/CoolColby23/PresenceFM`
- Judge instructions: run `swift run PresenceFM --demo` on macOS 15 or later;
  no music or service credentials are needed, and external publishing is paused
  during the demo.

After submission, open the hackathon dashboard and verify the entry says
**Submitted**, not merely **Published** or **Draft**.

## Optional release steps after the hackathon entry

The repository intentionally describes version 1.0.0 as a release candidate
until the manual account-, hardware-, and OS-dependent checks in
[QA-1.0.0-RC.md](QA-1.0.0-RC.md) are recorded. The public repository is enough
for Build Week; publishing a final 1.0 GitHub Release is not required for the
Devpost submission.
