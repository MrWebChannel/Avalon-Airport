# Your build loop (plain language)

GitHub is the one shared shelf. Any AI puts its work there as a **pull request**: a proposed change you can look at before accepting it. You accept it, then pull it onto your Mac.

## Every build

1. **Ask the AI for the change.** Say "follow AGENTS.md". It makes a branch, bumps the build number, and opens a pull request.
2. **Check the pull request on GitHub.** Open github.com/MrWebChannel/Avalon-Airport → **Pull requests**. Read the summary. Wait for the green check (GitHub compiled and tested the engine). A red X means the AI has more fixing to do; tell it.
3. **Merge.** Click **Merge pull request**, then **Confirm merge**. That puts the change on `main`.
4. **Pull it onto your Mac.** In Xcode (with `AvalonApp/Avalon.xcodeproj` open): **Integrate → Fetch Changes**, then **Integrate → Pull** and pick **origin/main**. If Xcode will not pull, open Terminal in the repo folder and type `git pull`.
5. **Run.** In Xcode press **Cmd-R**. The splash screen shows the build number. If it matches the pull request, you are running the new build.
6. **If something is wrong,** copy the error or describe what you saw and give it to the same AI. It fixes it in a new build.

## Undo

If a merged build is bad: on GitHub, open that pull request and click **Revert**. That creates a pull request that undoes it; merge that.

## Giving another AI access

Connect GitHub to that AI (each has its own GitHub connection in its settings) and allow only this repository. Tell it to read `AGENTS.md` first. Every AI follows the same loop, so the builds stay in one line: build 7 from Claude, build 8 from ChatGPT, and so on.
