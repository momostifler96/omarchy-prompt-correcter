# Prompt Corrector (momoledev.prompt-correcter)

Extension de barre omarchy : corrige un **message** (orthographe/grammaire) ou
transforme un texte en **prompt** clair et structuré, via n'importe quelle API
LLM compatible OpenAI.

## Utilisation

**Panneau (bouton ✍ dans la barre)** — ou **Super+Alt+C** si les raccourcis sont installés :

1. Le texte sélectionné à l'écran (sélection primaire) est pré-rempli, sinon le presse-papiers.
2. Choisir le mode :
   - **✉ Message** — corriger simplement (orthographe, grammaire, ponctuation)
   - **⚡ Prompt** — corriger et restructurer en un prompt efficace
3. Lancer, éditer le résultat si besoin, puis **📋 Copier** ou **⌨ Coller** dans la fenêtre active.
4. ⚙ ouvre les réglages (base URL, clé API, modèle, température, prompts système, copie auto).

**CLI (sans ouvrir le panneau)** :

```bash
omarchy-prompt-correcter message          # corrige le presse-papiers → résultat copié
omarchy-prompt-correcter prompt --paste   # restructure + colle dans la fenêtre active
```

Raccourcis suggérés (via `./bin/install.sh --bindings`) :

| Raccourci | Action |
|---|---|
| `Super+Alt+C` | ouvre/ferme le panneau |
| `Super+Alt+Shift+C` | corrige le presse-papiers et colle |
| `Super+Alt+Shift+P` | restructure le presse-papiers et colle |

## Configuration

Fichier : `~/.config/omarchy/prompt-correcter.json` (chmod 600 recommandé — il contient la clé API).
Éditable dans le panneau (⚙) ou à la main ; partagée entre le panneau et le CLI.

| Clé | Rôle |
|---|---|
| `baseUrl` | URL de base de l'API (sans `/chat/completions`) |
| `apiKey` | clé API (vide pour un serveur local) |
| `model` | nom du modèle |
| `temperature` | 0.0 – 2.0 |
| `autoCopy` | copier le résultat automatiquement après correction |
| `language` | langue de sortie : `auto` (langue du texte d'origine), `français`, `english`, `español`, `deutsch`, `português`, `italiano` |
| `systemPromptMessage` | prompt système du mode Message |
| `systemPromptRestructure` | prompt système du mode Prompt |

Exemples de providers :

| Provider | baseUrl | model |
|---|---|---|
| OpenAI | `https://api.openai.com/v1` | `gpt-4o-mini` |
| Ollama (local) | `http://localhost:11434/v1` | `llama3.1:8b` |
| OpenRouter | `https://openrouter.ai/api/v1` | `anthropic/claude-3.5-haiku` |
| Groq | `https://api.groq.com/openai/v1` | `llama-3.3-70b-versatile` |
| Mistral | `https://api.mistral.ai/v1` | `mistral-small-latest` |

## Fichiers

- `Widget.qml` — bouton de barre (✍)
- `Panel.qml` — panneau : modes, champs, réglages
- `bin/omarchy-prompt-correcter` — CLI (même config que le panneau)
- `bin/install.sh` — lie le CLI dans `~/.local/bin` (`--bindings` pour les raccourcis)
