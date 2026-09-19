<!-- markdownlint-disable no-inline-html -- required for typesetting purposes -->

<h1 align="center">
  <img
    src="https://is3-ssl.mzstatic.com/image/thumb/Purple112/v4/20/2b/3b/202b3b1c-c977-5445-365d-52593ed795f3/AppIcon-0-1x_U007emarketing-0-7-0-85-220.png/540x540bb.jpg"
    alt="TAT - 北科生活"
    style="
      width: 170px;
      height: 170px;
      border-radius: 22%;
      overflow: hidden;
      display: inline-block;
      vertical-align: middle;
    "
  />
</h1>

<h1 align="center">
<b>TAT</b>
<i><p><small>the Best NTUT Campus life assistant</small></p></i>
</h1>

<h6 align="center">

[![CI](https://github.com/NEO-TAT/tat_flutter/actions/workflows/build.yml/badge.svg?branch=master)](https://github.com/NEO-TAT/tat_flutter/actions/workflows/build.yml)

</h6>

## Introduction

TAT is a solution that simplifies campus life.

With this app, you can quickly view the course tables, classroom, grades, and calendar for each semester, as well as
quickly log in to the i-plus website without entering your account information.

Additionally, we offer common functions of i-Plus, such as downloading course files and viewing notifications.

Furthermore, you can view your friends' course tables and see what courses they have chosen.

The app supports Android and iOS/iPadOS platforms.

## Our story

Not long after the establishment of the **NTUT Programming Club (N.P.C.)**, the founding president created a campus life
app called TTS (with features similar to TAT), which was launched on the Google Play Store (due to its development in
Android native, there was no iOS version available).

Approximately 2 to 3 years after TTS was in use, a member of NPC had new ideas. He hoped to achieve the goal of a
dual-platform launch through the newly-released cross-platform open-source development framework (Flutter) by Google at
that time. As a result, the founding president of NPC worked with him to complete the initial version of TAT and
released it on both platforms.

Now, TAT has become a necessary tool for Northeastern students. In fact, this is due to the efforts of the student union
at that time.

However, what many people do not know is that TAT is a project fully developed by NPC and does not rely on any
assistance from the school or student union. Therefore, it does not have any obligations to the school or student union.
This makes every time the backend of the school has changes, all TAT users will immediately be at risk of encountering
unexpected errors.

## Get started

<a href="https://flutter.dev/">
  <img
    src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white"
    alt="get started with flutter"
  />
</a>

Due to the strong drive of [Flutter](https://flutter.dev/), the development of TAT is accomplished with half the effort.

- First, install [mise](https://mise.jdx.dev/) by following the
  [instructions](https://mise.jdx.dev/getting-started.html). This project uses mise to manage tool versions (Flutter,
  Java, and Ruby).

- Next, install [Android Studio](https://developer.android.com/studio) or
  [VSCode](https://code.visualstudio.com/) in your development environment, as Flutter and Dart officially recommend the
  use of these two solutions for development. However, if you believe that other editors/IDEs are a better choice for
  you, you may try installing them as well.

- Clone the code of TAT to your environment through [Git](https://git-scm.com/).

  ```bash
  git clone --recurse-submodules git@github.com:NEO-TAT/tat_flutter.git
  ```

- Install all required tools specified in `mise.toml`.

  ```bash
  mise install
  ```

- Verify that Flutter is correctly installed.

  ```bash
  flutter doctor -v
  ```

- Install the dependencies in the TAT project.

  ```bash
  flutter pub get
  ```

Once all dependencies are successfully installed, you can start doing whatever you want!

## Become contributor

<img src="https://i.imgur.com/7yYwMr1.webp" height="200" alt="TAT contributors">

If you are inclined to contribute to the improvement of this app, we welcome your participation at all times, regardless
of the form it may take.

While we certainly welcome more capable developers, contributing to this app does not necessarily require writing code.
If your expertise lies in areas such as UI design, animation design, project management, DevOps, planning, quality
management, automation, security, server-side, front-end web development, CI/CD, AI, ML, networking, IoT, multilingual
translation, accounting and finance, advertising, marketing, and promotion, among others, we also highly value your
involvement.

## Contributors

[![Contributors](https://img.shields.io/github/contributors/NEO-TAT/tat_flutter?color=ee8449&style=flat-square)](https://github.com/NEO-TAT/tat_flutter/graphs/contributors)

_Copyright © 2026 All rights reserved and owned by **N.P.C. 北科程式設計研究社**._
