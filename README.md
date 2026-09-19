<!-- markdownlint-disable no-inline-html -- required for typesetting purposes -->

<h1 align="center">
  <img
    src="assets/images/original.png"
    alt="QAQ"
    width="170"
    height="170"
  />
</h1>

<h1 align="center">
<b>QAQ</b>
<i><p><small>An independent campus life assistant for NTUT students</small></p></i>
</h1>

## Introduction

QAQ is an independently maintained campus life assistant for National Taipei University of Technology (NTUT)
students. It provides quick access to course tables, classrooms, grades, calendars, and supported NTUT web services.

QAQ supports Android and iOS/iPadOS.

> [!IMPORTANT]
> QAQ is an independent community-maintained project. It is not an official NTUT application and is not affiliated
> with or endorsed by NTUT or the maintainers of the upstream TAT project.

## Project lineage

QAQ began as a modified version of the GPL-3.0-licensed
[NEO-TAT/tat_flutter](https://github.com/NEO-TAT/tat_flutter) codebase. QAQ has been maintained separately by
`umeow0716` and contributors since September 2026.

Historical upstream copyright and contributor attribution is preserved in [NOTICE.md](NOTICE.md). References to the
upstream repository that remain in source comments document code provenance or historical issue context; they do not
indicate current project ownership or affiliation.

## Get started

<a href="https://flutter.dev/">
  <img
    src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white"
    alt="get started with flutter"
  />
</a>

- Install [mise](https://mise.jdx.dev/) by following the
  [instructions](https://mise.jdx.dev/getting-started.html). This project uses mise to manage tool versions (Flutter,
  Java, and Ruby).

- Install [Android Studio](https://developer.android.com/studio) or
  [VSCode](https://code.visualstudio.com/) in your development environment.

- Clone QAQ through Git.

  ```bash
  git clone --recurse-submodules git@github.com:umeow0716/qaq-app.git
  cd qaq-app
  ```

- Install all required tools specified in `mise.toml`.

  ```bash
  mise install
  ```

- Verify that Flutter is correctly installed.

  ```bash
  flutter doctor -v
  ```

- Install project dependencies.

  ```bash
  flutter pub get
  ```

## Contributing

Contributions to QAQ are welcome. Please keep changes compatible with the project's GPL-3.0 licensing requirements
and avoid introducing third-party branding or assets without an appropriate license or permission.

See [CONTRIBUTING.md](CONTRIBUTING.md) and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## License and attribution

QAQ is distributed under the **GNU General Public License version 3 (GPL-3.0)**. See [LICENSE](LICENSE) for the full
license text and [NOTICE.md](NOTICE.md) for upstream attribution and modification notices.

- Source repository: [umeow0716/qaq-app](https://github.com/umeow0716/qaq-app)
- QAQ contributors: [umeow0716/qaq-app contributors](https://github.com/umeow0716/qaq-app/graphs/contributors)
