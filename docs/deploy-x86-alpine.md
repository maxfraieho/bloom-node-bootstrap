# Deploy: x86-64 Alpine Linux Server

Інструкція для відтворення поточного налаштування на іншому x86-64 сервері з Alpine Linux.

---

## Передумови

```bash
# Alpine Linux (3.20+), x86_64, OpenRC
# Мінімум: 512 MB RAM, 5 GB вільного місця

apk add bash git python3 py3-pip nodejs npm curl openssh-client build-base
```

---

## 1. SSH ключ для GitHub

```bash
# Якщо ключа немає — генеруємо
ssh-keygen -t ed25519 -C "your@email.com" -f ~/.ssh/id_ed25519

# Показати публічний ключ — додати в GitHub → Settings → SSH keys
cat ~/.ssh/id_ed25519.pub

# SSH config
cat > ~/.ssh/config << 'EOF'
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
EOF
chmod 600 ~/.ssh/config

# Тест
ssh -T git@github.com
```

---

## 2. Git профіль

```bash
git config --global user.name "maxfraieho"
git config --global user.email "maxfraieho@gmail.com"
git config --global url."git@github.com:".insteadOf "https://github.com/"
git config --global safe.directory "*"
```

---

## 3. Claude Code

```bash
# Встановлення
npm install -g @anthropic-ai/claude-code --prefix ~/.local

# Додати до PATH (якщо не додано)
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.profile
source ~/.profile

# Логін через браузер або API key
claude login
# або: export ANTHROPIC_API_KEY=sk-ant-...
```

---

## 4. bloom-node-bootstrap

```bash
git clone git@github.com:maxfraieho/bloom-node-bootstrap.git ~/projects/bloom-node-bootstrap
cd ~/projects/bloom-node-bootstrap

# Виявлення профілю (або задати вручну)
bash install.sh --detect

# Для x86-64 Alpine сервера — використовувати готовий профіль
bash install.sh --plan --profile x86-alpine-server

# Повне розгортання
bash install.sh --apply --profile x86-alpine-server --yes
```

---

## 5. claude-codex-workflow (ctx, skills)

```bash
mkdir -p ~/.bloom/sources
git clone --depth=1 git@github.com:maxfraieho/claude-codex-workflow.git \
    ~/.bloom/sources/claude-codex-workflow

# Виправити REPO_ROOT в ctx (якщо потрібно)
python3 -c "
p = open('/home/YOUR_USER/.local/bin/ctx').read()
p = p.replace('Path(\"/home/YOUR_USER/claude-codex-skill\")',
               'Path(\"/home/YOUR_USER/.bloom/sources/claude-codex-workflow\")')
open('/home/YOUR_USER/.local/bin/ctx', 'w').write(p)
"

ctx doctor  # перевірка
```

---

## 6. bloom env

```bash
mkdir -p ~/.bloom

cat > ~/.bloom/env.sh << 'EOF'
export CTX_PROFILE="default"
export BLOOM_PROFILE="x86-alpine-server"
export PATH="$HOME/.local/bin:$HOME/.local/lib/node_modules/.bin:$PATH"
EOF

# Підключити до .profile
echo '. "$HOME/.bloom/env.sh"' >> ~/.profile
source ~/.profile
```

---

## 7. Claude skills

```bash
mkdir -p ~/.claude/skills

SKILLS_SRC=~/.bloom/sources/claude-codex-workflow/skills

for skill in \
  systematic-debugging writing-plans executing-plans test-driven-development \
  dispatching-parallel-agents subagent-driven-development requesting-code-review \
  receiving-code-review using-superpowers skill-creator writing-skills \
  frontend-design webapp-testing using-git-worktrees finishing-a-development-branch \
  mcp-builder brainstorming defense-in-depth root-cause-tracing \
  composition-patterns react-best-practices; do
  [ -d "$SKILLS_SRC/$skill" ] && cp -r "$SKILLS_SRC/$skill" ~/.claude/skills/
done

# Перевірка
ls ~/.claude/skills/ | wc -l   # має бути 20+
```

---

## 8. Claude hooks (settings.json)

```bash
mkdir -p ~/.claude/hooks

# Копіювати хуки з workflow
cp ~/.bloom/sources/claude-codex-workflow/hooks/*.sh ~/.claude/hooks/ 2>/dev/null || true

# bloom-специфічні хуки
cat > ~/.claude/hooks/bloom-pre-tool.sh << 'EOF'
#!/usr/bin/env bash
set +e
input="$(cat 2>/dev/null)"
[ -n "${BLOOM_HOOK_DEBUG:-}" ] && echo "[bloom pre-tool] $(date -u '+%H:%M:%S') $input" >> "${HOME}/.bloom/hook.log"
exit 0
EOF

cat > ~/.claude/hooks/bloom-post-tool.sh << 'EOF'
#!/usr/bin/env bash
set +e
input="$(cat 2>/dev/null)"
[ -n "${BLOOM_HOOK_DEBUG:-}" ] && echo "[bloom post-tool] $(date -u '+%H:%M:%S') $input" >> "${HOME}/.bloom/hook.log"
exit 0
EOF

chmod +x ~/.claude/hooks/*.sh

# settings.json
cat > ~/.claude/settings.json << 'EOF'
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/home/YOUR_USER/.claude/hooks/unified-skill-hook.sh"
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "/home/YOUR_USER/.claude/hooks/ctx-workflow-policy.sh"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/home/YOUR_USER/.claude/hooks/bloom-pre-tool.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/home/YOUR_USER/.claude/hooks/bloom-post-tool.sh"
          }
        ]
      }
    ]
  },
  "alwaysThinkingEnabled": true
}
EOF

# Замінити YOUR_USER на реальне ім'я
sed -i "s/YOUR_USER/$(whoami)/g" ~/.claude/settings.json
chmod 700 ~/.claude
```

---

## 9. Codex CLI

```bash
npm install -g @openai/codex --prefix ~/.local

# Налаштування (якщо використовуєте OpenAI)
# export OPENAI_API_KEY=sk-...

codex --version
```

---

## 10. chub та cgc

```bash
# chub (Context Hub docs search)
npm install -g @aisuite/chub --prefix ~/.local
chub --help

# cgc — grep shim (kuzu/falkordblite не компілюються на Alpine musl)
# вже встановлено bloom-node-bootstrap install.sh автоматично
cgc doctor
```

---

## Верифікація

```bash
cd ~/projects/bloom-node-bootstrap

# Здоров'я всіх компонентів
bash doctor.sh

# Workflow tools
ctx doctor

# Auth перевірка (не потребує API key якщо є claude login)
bash install.sh --verify --component tokens-config
```

**Очікуваний результат:**
```
Summary: 0 failure(s), 0 warning(s) — All checks passed.
ctx doctor → Environment: READY
tokens-config: verification PASSED (auth=claude.ai)
```

---

## Структура після розгортання

```
~/.claude/
├── settings.json          # hooks конфіг
├── hooks/                 # 8+ хуків (unified-skill, ctx-policy, bloom-pre/post)
└── skills/                # 28+ skills

~/.bloom/
├── env.sh                 # CTX_PROFILE, PATH
└── sources/
    └── claude-codex-workflow/   # workflow + skills source

~/projects/bloom-node-bootstrap/   # цей репозиторій
```

---

## Примітки по Alpine musl

- `kuzu` та `falkordblite` (CGC graph backends) не мають wheels для musl libc → використовується grep-shim
- `build-base` потрібен для pip пакетів що компілюють native extensions
- npm global install потребує `--prefix ~/.local` (без sudo)
- `chmod g-s ~/.claude` якщо директорія має setgid bit (perms=2700 → 700)
