<p align="center">
  <img src="https://img.shields.io/badge/AI-Powered-blueviolet?style=for-the-badge&logo=openai" />
  <img src="https://img.shields.io/badge/Status-Prototype-orange?style=for-the-badge" />
</p>

<h2 align="center">Building a Super Mario Maker-Like Game by Talking with AI</h2>
<h3 align="center">--- 0 lines of code written by hand ---</h3>

<p align="center">
  <a href="./README_zh.md"><b>🇨🇳 中文说明</b></a> | 
  <a href="./README.md"><b>🇬🇧 English</b></a>
</p>

---

### 📖 The Story: A Dream Realized in the Age of AI

I am 53 years old this year. It has been over 40 years since I wrote my very first BASIC program on an Apple II compatible machine in the 4th grade.

Over these four decades, I’ve worked in software development, telecommunications, and testing equipment, working my way up from a grassroots coder to management. In 2010, I caught the wave of mobile game startups. Although my team once built a game that reached #1 on the global charts, the venture ultimately ended in regret.

*Super Mario Bros.* is a game I grew up with. Back then, in a relatively closed-off China, we kids called it "Super Mary." We would play and wonder: why is this bearded uncle named "Mary"? It wasn't until many years later that we learned his real name was Mario.

When I first saw *Super Mario Maker*, I was amazed by the infinite creative possibilities it gave players, and I gradually formed the idea of making a similar game myself. But over the past dozen years, despite starting development a few times, I was forced to put it down again and again, overwhelmed by the sheer volume of work for a solo developer.

**Until AI came along.**

Starting last year, I began using AI more and more to assist with my programming—from debugging to setting up entire application frameworks. In fact, in a completely new domain I recently entered, I haven't written a single line of code myself in months.

Last weekend, a sudden thought struck me: Could I have AI help me recreate the original *Super Mario Bros.*? Since I still have my main job, I can only spare a few hours in my free time each day. I figured it would take a week or two, and I was even prepared to hit an insurmountable roadblock that would prove "AI isn't quite there yet."

To my surprise, just a few hours later, the first level was up and running on my computer.

By the next day, when World 1 was completely finished, my original plan of "finishing the whole game" changed. I realized that two-thirds of my time was actually spent preparing art assets and assembling the levels. The coding part was so incredibly smooth that it completely erased my last bit of doubt about AI's capability to deliver.

> **"If that's the case, could I let AI help me build a game like Super Mario Maker?"**

I decided to give it a try. This is not just a technical experiment for a veteran coder, but a chance to fulfill a small, lingering dream.

From today on, I plan to document every step of this project's development—whether it's a breakthrough, a deep pit I fall into, or the technical challenges and my solutions—and share them with everyone.

Let's see what kind of miracles AI can bring us in this era.

---

### 📖 The Pivot of LevelCraft
April 28

Yesterday, I posted my plan on Reddit and the Godot forums, and the reception wasn't exactly positive. The general consensus was basically: "Not optimistic, but good luck."

One helpful user even pointed me toward a post-mortem of a failed attempt to 'vibe-code' a Metroidvania game just a few days ago. https://forum.godotengine.org/t/post-mortem-of-my-failed-attempt-to-vibe-code-a-metroidvania-game/137567/19

Today, just as I finished adjusting the art assets and was about to dive into building the "Maker" mechanics, I found myself hesitating.

If 40 years of experience has taught me anything about my biggest flaw, it's that I change my mind very quickly. I've decided to pivot and find a smaller-scale game to test the waters first. I'll invest 2-3 weeks of serious effort into it; that should be enough time to see if this workflow actually yields results or not.

No sooner said than done. I dug up a very old game to use as a reference and got straight to work.

The new project is called Ricochet, which is also an action-based game with distinct levels. The plan is to rely completely on Claude Code AI for coding assistance. The ultimate goal is to deliver the game itself, an integrated level editor, and a fully functional website where users can create, play, and share their levels. The target: get it done in 4 weeks (giving myself a bit of a buffer).

If this doesn't fail, I'll slowly pick up the Super Mario Maker idea again. LevelCraft can then evolve into the backend infrastructure supporting the level editors for both games. Of course, I still have my primary, ongoing project—that remains the real priority. But for the next few weeks, I'm going all-in on Ricochet.

Wish me luck.

---

### 📅 Ricochet Development Logs
* [**000:** My AI Dev Team and Tech Stack ](./games/ricochet/devlogs/en/000.My%20AI%20Dev%20Team%20and%20Tech%20Stack.md)
* [**001:** Day 1 - Ricochet 开始3个小时 ](./games/ricochet/devlogs/en/001.Day%201%20-%20The%20first%20three%20hours%20of%20Ricochet.md)
* [**001:** Day 2 - Core Mechanics & Editor Foundations ](./games/ricochet/devlogs/en/002.Day%202%20-%20Core%20Mechanics%20&%20Editor%20Foundations.md)



*(More updates coming soon...)*

---
#### The Claude Transcripts

Up until now, my default language with Claude has always been Chinese. But for this project, I'm pushing myself to work entirely in English. I'll be dumping the complete, raw chat histories from the VS Code CLI here every day. Just in case anyone is curious to see exactly how this game is being willed into existence, prompt by prompt and step by step.

[Conversation 0428: Raw Log](./games/ricochet/devlogs/conversation%20with%20claude%202026-04028.JSONL)
[Conversation 0429: Raw Log](./games/ricochet/devlogs/conversation%20with%20claude%202026-04029.JSONL)

---

### 📅 Super Jumper Maker Development Logs

* [**000:** Tools & Tech Stack](./games/_archive_jump/devlogs/en/000.DevEnvironment.md)
* [**001:** Week 1 - The Birth of LevelCraft](./games/_archive_jump/devlogs/en/001.Week%201%20-%20The%20Birth%20of%20LevelCraft.md)
* [**002:** Day 10 - Cold Water from an Online Friends](./games/_archive_jump/devlogs/en/002.Day%2010%20-%20Cold%20Water%20from%20an%20Online%20Friends.md)


*(More updates coming later...)*

---
© 2026 AI Dream Builder. Built with 🤖 and ❤️.