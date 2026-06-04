# AI Agent Stack — Onboarding

Setup completo del stack de agentes de IA (Claude Code, Codex, Opencode) con SDD, intent-overlay y personalidad Gentleman-CO. Un comando instala todo; un comando mantiene todo al día.

---

## Instalación

```bash
curl -fsSL https://raw.githubusercontent.com/SoyJohnXD/agent-stack/main/bootstrap.sh | bash
```

Esto clona el repo, instala gentle-ai, configura Codex con SDD + MCP, instala el intent-overlay (clean-code-lab), aplica la personalidad Gentleman-CO en los tres agentes y deja el binario `agent-stack` disponible en PATH. Queda todo listo de una sola vez.

> Si también querés instalar Claude Code en el mismo paso, agregá `--with-claude`:
> ```bash
> curl -fsSL https://raw.githubusercontent.com/SoyJohnXD/agent-stack/main/bootstrap.sh | bash -s -- --with-claude
> ```

---

## Login (una sola vez)

Después del bootstrap, autenticá cada CLI:

```bash
claude login
codex login
opencode login
gentle-ai login
```

---

## Uso diario

```bash
# Mantener todo al día (binarios + configs)
agent-stack all

# Solo sincronizar configs (sin actualizar binarios)
agent-stack sync

# Ver estado de salud del stack
agent-stack doctor
```

---

## ¿Qué queda configurado?

| Agente | Lo que se instala |
|--------|------------------|
| **Claude Code** | gentle-ai base + persona Gentleman-CO + intent-overlay |
| **Codex** | SDD workflow + MCPs + persona Gentleman-CO |
| **Opencode** | gentle-ai base + SDD + persona Gentleman-CO + intent-overlay |

**Personalidad Gentleman-CO**: el agente guía paso a paso sin asumir conocimiento previo, bloquea malas prácticas aunque se le pidan, y verifica antes de darte la razón. Tono bogotano, "usted", serio en lo técnico.

---

## Verificar que todo quedó bien

```bash
agent-stack doctor
```

Debe mostrar todas las dependencias como `OK`. Si algo falla, el doctor indica qué está faltando.

---

## Windows

### Prerequisitos
- PowerShell 5.1+ (incluido en Windows 10/11)
- Git for Windows: https://git-scm.com/download/win
- Python 3: https://python.org/downloads/
- Opcional (mejora la experiencia): winget, scoop o chocolatey para instalar OpenCode automáticamente

### Instalación
```powershell
# 1. Clonar el repo
git clone https://github.com/SoyJohnXD/agent-stack.git "$env:USERPROFILE\.agent-stack"

# 2. Configurar la ruta de librerías
$env:AGENT_STACK_LIB = "$env:USERPROFILE\.agent-stack\lib"

# 3. Ejecutar bootstrap
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.agent-stack\bootstrap.ps1"
```

### Después de instalar
- Abrí una **nueva** ventana de PowerShell — el PATH se actualiza en sesiones nuevas
- Verificá con: `agent-stack doctor`
- El comando `agent-stack` invoca `agent-stack.ps1` desde `$env:LOCALAPPDATA\Programs\agent-stack\`

### Variable de entorno importante
`$env:AGENT_STACK_LIB` debe apuntar a la carpeta `lib/` del repo clonado.
El bootstrap la configura automáticamente, pero si ejecutás scripts manualmente, asegurate de tenerla seteada.
