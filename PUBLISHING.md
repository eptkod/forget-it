# Publish forget it on GitHub

The source folder is ready for a public repository. The compiled DMG is kept out of Git history and uploaded separately to a GitHub Release. You need a GitHub account and an empty repository; the included script handles the local Git setup and source upload.

## 1. Create the public repository

1. Sign in to GitHub and open [New repository](https://github.com/new?name=forget-it&visibility=public).
2. Set the name to `forget-it` (or another name you prefer) and visibility to **Public**.
3. Leave **Add a README**, **Add .gitignore**, and **Choose a license** empty. These project files already exist locally; choose a license later if you want to grant reuse rights.
4. Click **Create repository**. Copy its HTTPS URL, such as `https://github.com/YOUR-USERNAME/forget-it.git`.

## 2. Upload the source

In Finder, open the `forget it` folder. Open Terminal, type `cd ` (with a space), drag that folder into Terminal, and press Return. Then run this command with your repository URL:

```sh
bash scripts/publish-source.sh https://github.com/YOUR-USERNAME/forget-it.git
```

The script lists the files before asking you to publish them. Git may ask you to sign in to GitHub. If it reports that your Git author name or email is missing, set them with `git config --global user.name "Your Name"` and `git config --global user.email "you@example.com"`, then rerun the script. That email is visible in public commits unless you use a GitHub no-reply address.

The private calendar reference image, local builds, app bundle, and DMG are excluded from source commits by `.gitignore`. The app preview and original brand artwork are included. Review the listed files before answering `y`.

## 3. Add the Mac download

The current local `dist/forget-it.dmg` is an **ad-hoc signed development build**, not a notarized public release. Before distributing it, check real notification delivery and opening a notification, and test installation on another Apple Silicon Mac running macOS 26 or later. The outstanding checks are in [VALIDATION.md](VALIDATION.md).

When you are ready to share a build:

1. On your GitHub repository page, open **Releases → Draft a new release**.
2. Create tag `v0.2.0`, set the title to `forget it 0.2.0`, and describe the tested features and remaining limitations.
3. Drag `dist/forget-it.dmg` into the release assets box. Mark it as a **pre-release** while the checks above remain open, then publish.
4. Link your website's Download button to `https://github.com/YOUR-USERNAME/forget-it/releases/latest` once you have a release suitable for that link. For a pre-release, copy that release's specific URL instead.

GitHub's generated **Source code** ZIP is not the app installer. Visitors should download the `.dmg` asset. The DMG stays on GitHub, so your website only needs to link to it.

Public visibility makes the code readable. This repository currently has no software license, so others do not receive general permission to reuse or redistribute the code. Add a license if you want to grant those rights.
