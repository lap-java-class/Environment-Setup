# Java 21 + Sublime Text Setup

Set up a computer for writing Java programs. These scripts detect your operating
system and processor, download Eclipse Temurin **JDK 21**, install Sublime Text,
and configure Java commands for your terminal.

**Install directly from GitHub using Command Prompt or Terminal. You do not need
Git, Python, Java, or a downloaded ZIP of this repository.**

Start at [Before you begin](#before-you-begin), then choose
[Windows](#windows-install-from-command-prompt) or
[macOS/Linux](#macoslinux-install-from-terminal).

Repository: [lap-java-class/Environment-Setup](https://github.com/lap-java-class/Environment-Setup).
The commands below use its `main` branch. They become available after the scripts
are uploaded there and the repository is public. Until then, use the local-file
instructions below. A private or unpublished repository will return a download
error; setup will not run.

## What gets installed?

- **JDK 21:** the Java Development Kit. It includes `javac`, which compiles your
  code, and `java`, which runs it. Setup selects the latest available Temurin 21
  patch release at the time you run it.
- **Sublime Text:** an editor for writing your code. New installations use stable
  build **4215**. A detected existing installation is reused.
- **JAVA_HOME:** an environment variable pointing to the installed JDK.
- **PATH:** the list of folders your terminal searches for commands. Setup adds
  Java and Sublime Text so you can type `java`, `javac`, and `subl`.

Sublime Text can be evaluated for free; continued use requires purchasing a
[Sublime Text license](https://www.sublimetext.com/download). This project does
not provide a license or register the editor for you.

Setup verifies Java by compiling and running a small temporary program. It does
not configure Sublime plugins or a Java build shortcut. The tutorial below uses
Sublime to edit code and the terminal to compile and run it.

## Supported targets and current limitations

| Computer | Processor | First-version support |
| --- | --- | --- |
| Windows 10/11 | Intel/AMD 64-bit (x64) | Supported by the Windows script |
| Windows | ARM64 or 32-bit x86 | Detected, then stopped with an explanation |
| macOS 11 or newer | Apple Silicon (M-series) or Intel x64 | Supported by the Unix script; Apple Silicon is detected even under Rosetta |
| Linux desktop with glibc 2.28+ | x64 or ARM64 | Supported by the Unix script, subject to the dependencies below |
| Alpine/musl Linux, 32-bit Linux, other architectures | Any | Not supported by this version |

These are implementation targets, **not a claim that every combination has been
tested on a real device**. Full installations still need testing on each target.
Windows ARM64 is deliberately excluded from this first version; that does not
mean that Java or Sublime cannot run on that platform through other installers.

On macOS/Linux your login shell must be **Bash or Zsh**. Fish and other shells
need manual environment configuration and are rejected before installation.
Linux needs a graphical desktop to open Sublime. Headless servers and WSL are
not intended targets. A compatible CPU alone does not guarantee that all Linux
desktop libraries are installed.

## Before you begin

1. Connect to the internet. Downloads come from Adoptium, GitHub, and Sublime HQ.
2. Allow roughly **1 GB of free disk space** for archives, extracted files, and
   the finished installation. Leave extra space if you keep several JDK updates.
3. Save your work and close Sublime Text if it is already open.
4. On Windows, use an account that can approve an administrator prompt.
5. On macOS/Linux, run setup as your normal user, **without `sudo`**. Software is
   installed for that account. Linux prerequisite installation may need `sudo`.
6. Understand that setup makes Java 21 your default Java in the configured
   environment. Other Java installations are kept, but programs that rely on a
   different default version may need their own Java settings.

You can run **preview mode** first. The curl command still downloads the setup
script, but preview does not download installers, create installation logs, or
change settings. It detects your platform and prints the plan. It does not prove
that installer downloads, permissions, or desktop dependencies will work.

## Windows: install from Command Prompt

### 1. Open Command Prompt

Open **Start**, type **Command Prompt**, and open it. You can use a normal window:
the script will ask for administrator access when it is time to install.

If Windows Terminal opens PowerShell instead, open a **Command Prompt** tab.
The command below uses Command Prompt syntax.

### 2. Paste this command and press Enter

```cmd
curl.exe -fL --retry 3 "https://raw.githubusercontent.com/lap-java-class/Environment-Setup/main/setup-windows.ps1" -o "%TEMP%\java-sublime-setup.ps1" && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\java-sublime-setup.ps1"
```

The entire code block is **one command**. Copy it without the surrounding
backticks. You can run it from any folder.

Here is what happens:

1. `curl.exe` downloads the Windows script from this repository over HTTPS.
2. It saves the file as `java-sublime-setup.ps1` in your temporary folder.
3. `&&` starts PowerShell **only if the download finishes successfully**.
4. The script detects your device and displays the installation plan.
5. Windows asks for administrator access. Approve the prompt, or supply an
   administrator's credentials if your account requires them.
6. Installation runs in an elevated background process. Keep your original
   Command Prompt window open; it displays live progress and a timestamped
   `[SUCCESS]` message after each completed step, followed by success or failure.
7. The detailed installation log is saved under
   `C:\ProgramData\JavaSublimeSetup\logs` on a typical Windows installation.

The background installation may take several minutes. Its progress messages
appear automatically in your original window; the full transcript remains in
the log file. Each run has a unique log, so another run's messages are not mixed
into your terminal. To see all tool output directly, open Command Prompt using
**Run as administrator** before running the same command. Preview mode never
requests administrator access.

For example, a successful Windows run includes these messages (with timestamps):

```text
[SUCCESS] Step 1/4 complete: Java 21 is installed and tested.
[SUCCESS] Step 2/4 complete: Sublime Text executable is present.
[SUCCESS] Step 3/4 complete: system JAVA_HOME and PATH configured.
[SUCCESS] Step 4/4 complete: this setup process resolves java to the selected JDK.
```

Downloads, checksum/signature checks, and Java test runs also report success as
they finish. Reused software is identified. A failed step produces an error and
does not receive a step-success message; later steps do not run.

`-ExecutionPolicy Bypass` applies only to the launched PowerShell process; it
does not permanently change the computer's policy. An organization's policy can
still block execution.

### 3. Preview first, if you prefer

This downloads the script and displays the plan, without installing software or
changing environment settings:

```cmd
curl.exe -fL --retry 3 "https://raw.githubusercontent.com/lap-java-class/Environment-Setup/main/setup-windows.ps1" -o "%TEMP%\java-sublime-setup.ps1" && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\java-sublime-setup.ps1" -Preview
```

The download itself writes the script file. The script's preview does not create
installation folders or logs. You can open the saved script in a text editor
before running it.

### 4. Refresh your environment

After **Setup complete** appears, save your work, **sign out of Windows and sign
back in**, then open a new Command Prompt or PowerShell window. This refreshes
environment variables for all your applications.

Java normally goes into a version-specific folder inside
`C:\Program Files\JavaSublimeSetup`. It is an archive installation, so it does
not get its own Installed Apps entry. Sublime uses its official installer and
normally appears in the Start menu.

Then follow [Check your installation](#check-your-installation).

## macOS/Linux: install from Terminal

### 1. Open Terminal

- **macOS:** press **Command + Space**, type **Terminal**, and press **Return**.
- **Linux:** open **Terminal** from your applications menu.

Use your normal user account, **without sudo**. Your login shell must be Bash or
Zsh, even though Bash runs the installer in both cases.

### 2. Linux only: check prerequisites

On macOS, the script uses tools already supplied with the operating system.
You do not need Homebrew.

On Linux, use a desktop system with glibc 2.28 or newer, Bash, `curl`, `tar`,
`xz`, `gpg`, `sha256sum`, and common Unix utilities. Sublime needs GTK 3 desktop
libraries. Ubuntu 22.04/24.04, Debian 12, and recent Fedora desktops are intended
targets; full installations on these distributions still need real-device tests.

If tools are missing, install prerequisites with your distribution's commands:

**Ubuntu/Debian:**

```bash
sudo apt-get update
sudo apt-get install curl ca-certificates tar xz-utils gnupg libgtk-3-0
```

On Ubuntu 24.04 and other systems where the package was renamed, use
`libgtk-3-0t64` instead of `libgtk-3-0`. A standard desktop may already provide it.

**Fedora:**

```bash
sudo dnf install curl ca-certificates tar xz gnupg2 gtk3
```

`sudo` may ask for your login password. No characters appear as you type it;
press **Enter** when finished. These prerequisite commands need administrator
access. The actual setup command below does not.

### 3. Paste this command and press Enter

```bash
curl -fL --retry 3 "https://raw.githubusercontent.com/lap-java-class/Environment-Setup/main/setup-unix.sh" -o "$HOME/java-sublime-setup.sh" && bash "$HOME/java-sublime-setup.sh"
```

You can run this from any folder. It downloads the script to your home folder,
then runs it only after a successful download. It does not download the whole
repository. Running the command again replaces the previously downloaded script.

Wait for the three numbered stages to finish. Each completed stage prints a
timestamped `[SUCCESS]` message to Terminal and the setup log. Java goes into
`~/.local/share/java-sublime-setup/jdks`, where `~` means your home folder.

- **macOS:** Sublime goes into `~/Applications`. A copy already there or in
  `/Applications` is reused. The downloaded app supports Intel and Apple Silicon.
  Setup checks its code signature and Gatekeeper assessment before installation.
- **Linux:** a new Sublime installation goes into
  `~/.local/share/java-sublime-setup`, with a **Sublime Text (Java Setup)**
  application-menu launcher. An existing `subl` command on PATH is reused.

### 4. Preview first, if you prefer

```bash
curl -fL --retry 3 "https://raw.githubusercontent.com/lap-java-class/Environment-Setup/main/setup-unix.sh" -o "$HOME/java-sublime-setup.sh" && bash "$HOME/java-sublime-setup.sh" --preview
```

This saves the script and displays the plan. It does not install software or edit
your shell configuration. Open the saved file in a text editor to inspect it.

### 5. Reopen Terminal

Quit Terminal and open it again after setup finishes. With Zsh, setup updates
`~/.zshrc` and `~/.zprofile` (or their equivalents under an exported `ZDOTDIR`).
With Bash, it updates `.bashrc` and the applicable login startup file.

Run `subl` to open Sublime, or find it in Applications on macOS or your Linux
application menu. On macOS, a per-user installation appears in Finder under
**Go → Home → Applications**.

### Optional: pipe directly into Bash

The script also supports this form, which does not keep a downloaded script:

```bash
(set -o pipefail; curl -fsSL --retry 3 "https://raw.githubusercontent.com/lap-java-class/Environment-Setup/main/setup-unix.sh" | bash)
```

For a preview:

```bash
(set -o pipefail; curl -fsSL --retry 3 "https://raw.githubusercontent.com/lap-java-class/Environment-Setup/main/setup-unix.sh" | bash -s -- --preview)
```

The parentheses keep `pipefail` local to this command. It makes a failed download
produce a failure status even if Bash received no script. The download-and-run
command above remains the main beginner flow: it completes the download before
starting execution and leaves a file available for inspection.

## Alternative: download the ZIP or run local files

If you prefer to download the entire project:

1. Open [the repository](https://github.com/lap-java-class/Environment-Setup).
2. Click **Code → Download ZIP**.
3. Extract the ZIP. On Windows, right-click it and choose **Extract All**.
   On macOS, double-click it. On Linux, use your file manager's extract option.
4. Open the extracted folder. It should contain `README.md`,
   `setup-windows.ps1`, `setup-unix.sh`, and `examples`.
5. Open Command Prompt or Terminal and use `cd` to move into that folder.
   Put the folder path in quotes if it contains spaces.
6. Run the appropriate local command:

**Windows, from Command Prompt or PowerShell:**

```text
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup-windows.ps1
```

**macOS/Linux:**

```bash
bash setup-unix.sh
```

Add `-Preview` on Windows or `--preview` on macOS/Linux to inspect the plan.
Do not run files from inside an unextracted ZIP.

## Check your installation

In a **new terminal**, run these commands one at a time:

```text
java -version
javac -version
subl --version
```

The Java commands should show version **21** (for example, `21.0.x`). The exact
patch number changes as updates are released. Sublime should print its build
number; an existing installation can have a different build from this project.

To see the Java installation folder:

**Windows PowerShell:**

```powershell
$env:JAVA_HOME
Get-Command java
```

**Windows Command Prompt:**

```cmd
echo %JAVA_HOME%
where java
```

`where java` can list several Java installations. That is normal: the selected
JDK should appear first. Setup checks the first executable match for both
`java.exe` and `javac.exe`; an older Java installation later in PATH is allowed.

**macOS/Linux:**

```bash
echo "$JAVA_HOME"
command -v java
```

Existing aliases, functions, user-specific `JAVA_HOME` values on Windows, or
later commands in shell startup files can override setup. If the output is
unexpected, see troubleshooting below.

## Write and run your first Java program

The curl flow does not download the example folder. Create your own practice
folder and file using these steps; no repository download is needed.

1. In a new terminal, create a practice folder and move into it.

   **Windows Command Prompt:**

   ```cmd
   if not exist "%USERPROFILE%\java-practice" mkdir "%USERPROFILE%\java-practice"
   cd /d "%USERPROFILE%\java-practice"
   ```

   **Windows PowerShell:**

   ```powershell
   New-Item -ItemType Directory -Force -Path "$HOME\java-practice"
   Set-Location "$HOME\java-practice"
   ```

   **macOS/Linux:**

   ```bash
   mkdir -p "$HOME/java-practice"
   cd "$HOME/java-practice"
   ```

2. Open a new file in Sublime with this command:

   ```text
   subl HelloWorld.java
   ```

3. Paste the following code into the file. Save with **Ctrl + S** on Windows/Linux
   or **Command + S** on macOS. If the file already exists, save your existing
   work before replacing its contents.

   ```java
   public class HelloWorld {
       public static void main(String[] args) {
           System.out.println("Hello, Java 21!");
       }
   }
   ```

4. Return to the terminal you used in step 1. Compile your source file:

   ```text
   javac HelloWorld.java
   ```

   Success usually produces no message. It creates a `HelloWorld.class` file.

5. Run the compiled program:

   ```text
   java HelloWorld
   ```

   You should see `Hello, Java 21!`. Do not add `.java` or `.class` to this command.

6. Change the message in Sublime, save the file, and repeat steps 4 and 5.

The file name and class name must match exactly, including capital letters.

## Rerunning, updates, and existing installations

- Run the same setup command again to fetch the latest available **Java 21**
  patch. It never intentionally switches to a different major Java version.
- The exact downloaded release is identified by its SHA-256 checksum. If that
  release already exists in this project's installation directory, it is reused
  and tested again. An unrelated existing JDK is preserved; it is not adopted.
- Older JDK folders remain so existing references are not broken. They are not
  automatically deleted, and updates are not scheduled in the background.
- Existing Sublime installations in the documented locations are reused.
  Update Sublime through its own updater or the installation method you used.
  Linux archive installations can be updated by the project maintainer changing
  `SUBLIME_BUILD` and distributing an updated script; remove the old setup's
  PATH entry or uninstall it first if it is being reused.
- Windows PATH entries for the currently selected JDK/Sublime folder are not
  duplicated. Entries for previous JDK releases may remain later in PATH.
- Unix startup-file loader lines are not duplicated on reruns. Previous profile
  files and generated environment settings are backed up before changes.
- Setup stops on errors, but it is **not a transaction**: successfully installed
  software from an earlier step may remain when a later step fails. Resolve the
  reported error and rerun. Do not run multiple copies of setup simultaneously.

## Troubleshooting

### Windows: connection resets or "remote name could not be resolved"

These messages describe network failures. "Could not be resolved" means the
hostname could not be translated into an IP address; it does not mean the laptop
is too slow. A fast speed test also does not establish that a particular server
is reachable. A connection reset can have several causes, including routing,
VPN/proxy behavior, security software, or a remote server. The error alone does
not prove censorship or identify which component interrupted the connection.

The initial script comes from `raw.githubusercontent.com`. Java downloads use
Adoptium and GitHub release servers, while Sublime uses `download.sublimetext.com`.
Successfully downloading the script does not prove those other servers work.

The Windows installer uses `curl.exe` for metadata and installer downloads. It
retries transient failures up to five times with increasing waits, and logs the
server, curl exit code, and HTTP status. Each attempt restarts its download;
failed partial files are never installed. A working Java installation from an
earlier attempt can be reused. Certificate, checksum, and publisher checks remain
enabled. Persistent DNS failures still need the connection problem resolved.

After downloading the updated script, run this in **Command Prompt** on the
affected laptop:

```cmd
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\java-sublime-setup.ps1" -DiagnoseNetwork
```

To download the updated script and run diagnostics in one command:

```cmd
curl.exe -fL --retry 3 "https://raw.githubusercontent.com/lap-java-class/Environment-Setup/main/setup-windows.ps1" -o "%TEMP%\java-sublime-setup.ps1" && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\java-sublime-setup.ps1" -DiagnoseNetwork
```

This mode makes small network requests only. It does not install software,
request administrator access, or change DNS/proxy settings. It prints status
codes for the script host, Adoptium, GitHub, and Sublime. A successful small
request does not prove a large download or redirected asset CDN will work.
When testing a VPN, establish the connection first and keep it unchanged for
the entire run. Compare results using another connection, such as a mobile
hotspot, if available. Share the diagnostic output to narrow down the cause.

If a log says Java compiled successfully but Sublime failed, the Java files may
already be installed. The environment configuration happens after the Sublime
step, so `java` on PATH may not have been updated yet. Finish a successful setup
before relying on its final environment configuration.

| Problem | What to do |
| --- | --- |
| Script/file not found | Copy the complete curl command, including the output path. If using the ZIP alternative, extract it first and use `dir` or `ls` to check your folder. |
| GitHub download returns 404 | The repository must be public and the script must exist on `main`. A private repository, missing file, or unpublished branch can produce this error. |
| curl is not recognized on Windows | Use an up-to-date Windows installation with curl.exe, or use the ZIP alternative. |
| Windows asks for administrator access | Approve the prompt. If it was cancelled, run the command again. To see detailed output directly, run from Command Prompt opened as administrator. |
| PowerShell blocks the script | Use the exact `powershell.exe ... -ExecutionPolicy Bypass ...` command above. If a work/school policy blocks it, contact the administrator. |
| Java is missing or still shows another version | Sign out/in on Windows; reopen Terminal on macOS/Linux. Inspect command resolution using the checks above. Look for aliases or other Java managers overriding PATH. |
| Windows JAVA_HOME still shows another JDK | Open Start, search **Edit environment variables for your account**, and inspect a user-level JAVA_HOME. A user value overrides the system value; update it to the setup's reported folder or remove only that conflicting variable. |
| Linux reports a missing shared library | Install your distribution's GTK 3 desktop/runtime dependencies. Capture the named library and ask your distro's support resources if unsure. |
| Linux says a command such as gpg or xz is missing | Install the prerequisites above, then rerun. |
| Download fails | Check internet access, disk space, and access to raw.githubusercontent.com, api.adoptium.net, github.com, GitHub release downloads, and download.sublimetext.com. Rerun after correcting the problem. |
| Checksum or signature verification fails | Stop. Retry on a reliable connection. Do not remove verification checks. The download or upstream signing metadata may need investigation. |
| An existing JDK folder is incomplete | Read the failing path in the log. Remove only that incomplete checksum-named folder inside this project's installation directory, then rerun. Do not delete other Java installations. |
| Unsupported device or shell | Check the support table. Use the vendors' manual installers or adapt the script for that platform. |
| javac says the public class needs a different file name | Save the example as exactly `HelloWorld.java`, not `HelloWorld.java.txt`. |

Logs:

- **Windows:** `%ProgramData%\JavaSublimeSetup\logs` (normally
  `C:\ProgramData\JavaSublimeSetup\logs`). `environment-before-*.json` records
  the previous machine PATH and JAVA_HOME for each run that reaches configuration.
- **macOS/Linux:** `~/.local/share/java-sublime-setup/logs`.

If a background elevated Windows run fails before a log is created, rerun from
Command Prompt opened as administrator to see the error. Other early errors
appear in your terminal. Logs can include your username and local folder paths;
review them before posting them publicly.

## Uninstall or undo the configuration

### Windows

1. Close programs using this JDK.
2. Open Start and search for **Edit the system environment variables**. Open
   **Environment Variables** and use the **System variables** section.
3. Remove PATH entries that point inside `JavaSublimeSetup`. Restore the previous
   JAVA_HOME value from the saved `environment-before-*.json`, or remove it if
   it was previously absent. Use the earliest relevant backup to undo the initial
   setup. Do not replace your entire current PATH if other software has changed
   it since the backup.
4. Delete only the `JavaSublimeSetup` folder inside Program Files after checking
   that nothing still needs its JDKs. Administrator permission is required.
5. If this setup installed Sublime and you want to remove it too, uninstall it
   through **Settings → Apps**. Remove its PATH entry if no longer needed. Keep
   an existing Sublime installation you were already using.
6. Sign out and back in.

### macOS/Linux

1. Close programs using the JDK.
2. Open the startup files setup changed (`.zshrc`/`.zprofile`, or `.bashrc` and
   the applicable Bash login file). Hidden files start with a dot. In macOS
   Finder, **Command + Shift + .** toggles hidden files; many Linux file managers
   use **Ctrl + H**.
3. Remove the `# Java + Sublime Setup` comment and its following loader line
   from each file. Backups have `.java-setup-backup-...` suffixes. Restore an
   entire backup only if doing so will not discard edits made afterward.
4. Delete `~/.local/share/java-sublime-setup` after checking that no applications
   still need its contents. This also deletes setup logs and environment backups.
5. On macOS, remove `~/Applications/Sublime Text.app` only if this setup created
   it and you no longer need it. An existing copy in `/Applications` was reused.
6. On Linux, remove `~/.local/share/applications/java-sublime-setup.desktop` if
   present. Reused system/package-manager Sublime installations are unaffected.
7. Reopen your terminal.

## Repository contents and validation

```text
README.md                 Beginner instructions
setup-windows.ps1         Windows PowerShell installer
setup-unix.sh             macOS/Linux Bash installer
examples/HelloWorld.java  Your first Java program
tests/                    Non-installing checks for maintainers
.gitattributes            Keeps shell-script line endings compatible
.gitignore                Excludes logs and compiled Java files
```

Maintainers can run non-installing checks:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\check-windows.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\check-downloads.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\check-java-path.ps1
```

```bash
bash -n setup-unix.sh
bash tests/check-unix.sh
```

These checks validate parsing, platform rejection/detection, environment
configuration, stdin execution, preview mode, and mocked Windows elevation
(including path quoting, cancellation, and exit codes), and simulated download
failures (DNS errors, connection resets, HTTP errors, and incomplete responses).
They do not replace testing downloads,
native installers, permissions, and application launch on Windows, Intel Mac,
Apple Silicon Mac, and Linux x64/ARM64. Before publishing a release, run complete
installations on disposable target machines, including a second run, an existing
Java/Sublime installation, a home path containing spaces, and a failed download.

## Publishing the commands on GitHub

For the repository maintainer:

1. Upload this project's files to the root of the `main` branch in
   [lap-java-class/Environment-Setup](https://github.com/lap-java-class/Environment-Setup).
   Keep both scripts in the root, with their existing file names.
2. Make the repository public if users should install without signing in.
3. Open each script on GitHub and select **Raw**. Confirm the URL matches the
   corresponding `raw.githubusercontent.com` URL in the commands above.
4. Test the remote **preview** commands first, then test complete installations
   on disposable supported machines. Preview does not test the UAC prompt.
5. Once a version is tested, create a release tag such as `v1.0.0` through GitHub's
   Releases page. For commands pinned to that release, replace `/main/` with
   `/v1.0.0/` in the raw script URLs. Do not advertise that tag before it exists.

`main` downloads the current script and can change as commits are uploaded. A
release tag makes the intended script version explicit; a full commit SHA in
the same URL position pins it to a particular commit. All user-facing download
commands use HTTPS, so users do not need Git or an SSH key.

Official references:

- [Temurin installation](https://adoptium.net/installation/)
- [Adoptium API download examples](https://github.com/adoptium/api.adoptium.net/blob/main/docs/cookbook.adoc)
- [Temurin supported platforms](https://adoptium.net/supported-platforms)
- [Sublime Text downloads](https://www.sublimetext.com/download)
- [Sublime Linux packages](https://www.sublimetext.com/docs/linux_repositories.html)

The repository contains scripts and documentation. Installers are downloaded
from their vendors at runtime; do not upload downloaded installer binaries or
personal logs to this repository.
