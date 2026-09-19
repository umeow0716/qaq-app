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

<h6 align="center">

[![CI](https://github.com/umeow0716/tat_umeow/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/umeow0716/tat_umeow/actions/workflows/build.yml)

</h6>

## Introduction

QAQ is an independently maintained derivative of
[NEO-TAT/tat_flutter](https://github.com/NEO-TAT/tat_flutter), the GPL-3.0-licensed TAT project for National Taipei
University of Technology (NTUT) students.

With this app, you can quickly view course tables, classrooms, grades, and calendars for each semester, as well as use
supported NTUT web services from one place.

QAQ supports Android and iOS/iPadOS platforms.

> [!IMPORTANT]
> QAQ is an independent community-maintained project. It is not affiliated with, endorsed by, or an official release
> of N.P.C. 北科程式設計研究社, NEO-TAT, or National Taipei University of Technology.

## Project lineage

QAQ is based on the original TAT Flutter codebase maintained at
[NEO-TAT/tat_flutter](https://github.com/NEO-TAT/tat_flutter). The upstream project was developed by N.P.C. 北科程式設計研究社
and its contributors.

This fork contains substantial modifications maintained separately by `umeow0716` since September 2026. Upstream TAT
and the current N.P.C. implementation remain separate projects with their own maintainers, branding, and releases.

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
  git clone --recurse-submodules git@github.com:umeow0716/tat_umeow.git
  cd tat_umeow
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

## License and attribution

The original TAT work is copyright its respective N.P.C. 北科程式設計研究社 authors and contributors.
QAQ modifications are copyright © 2026 `umeow0716` and contributors.

This project is distributed under the **GNU General Public License version 3 (GPL-3.0)**. See [LICENSE](LICENSE) for the
full license text. Modified versions and binary releases must continue to comply with the GPL-3.0 requirements,
including providing the corresponding source code and preserving applicable notices.

- Original project: [NEO-TAT/tat_flutter](https://github.com/NEO-TAT/tat_flutter)
- Original contributors: [NEO-TAT/tat_flutter contributors](https://github.com/NEO-TAT/tat_flutter/graphs/contributors)
- QAQ contributors: [umeow0716/tat_umeow contributors](https://github.com/umeow0716/tat_umeow/graphs/contributors)
