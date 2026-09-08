# Agent instructions

Read [`CLAUDE.md`](CLAUDE.md), then [`ai/context.md`](ai/context.md) before making
changes. Task-specific procedures live in [`ai/playbooks/`](ai/playbooks).

The short version: this repository holds one Azure Container Registry (Terraform) and
three CI pipelines that implement one identical build contract. Most changes touch more
than one place — `ai/context.md` has the change matrix that says which.
