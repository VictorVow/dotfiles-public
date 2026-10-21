---
name: git-commit
description: Make a git commit of the changes from this Claude session.
---
- `git add` only the files touched by this session. If there are no files touched by this
  session then give a summary of what files have been changed outside of this session and
  give a commit message suggestion.
- If executed not in a git repo, then check the child directories for which contain git repos.
- git commit messages should follow the Conventional Commit structure i.e.
<type>[optional scope]: <description>

[optional body]

[optional footer]
  - Examples:
    - feat: allow provided config object to extend other configs
    - docs(lang): correct spelling of CHANGELOG
    - fix: minor typos in code

      see the issue for details on the typos fixed

      fixes issue #12
- Aim to have a descriptive commit message body unless the change is trivial
  - Examples:
    - feat(api.ts): add OpenAI class with generateCommitMessage method

      This commit adds a new OpenAI class with a generateCommitMessage method that uses
      the OpenAI API to generate a commit message based on an array of messages. The
      method takes an array of ChatCompletionRequestMessage objects and returns a
      Promise that resolves to a ChatCompletionResponseMessage object. The OpenAI
      class is exported as a singleton instance named api.
    - fix(README): fixed two small typos
- Do not `git push` unless the remote is a example.com URL. Check with `git remote -v`
  first — never infer the remote from commit authors, branch names or repo contents. If the
  remote is not a example.com URL, then don't push unless it's necessary because a pull
  request, workflow action or something else in our intended next steps needs the commit pushed first.

