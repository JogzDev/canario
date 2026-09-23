# Marca do Seam

Identidade escolhida pelo JP em 23/09/2026: a **fita métrica** desenhando o S.
"Seam: moda, medida" / "Seam: Fashion, Measured".

- `AppIcon.appiconset/` — ícone pronto para o Xcode, nas três aparências do iOS
  (clara, escura e tingida). Entra no app quando a branch da 2.0 trocar o ícone.
- `pranchas/` — as pranchas apresentadas: as três direções estudadas, a marca
  (nome, cor, tipo) e o ícone final em contexto.
- `fonte/` — o desenho é código SwiftUI renderizado com as fontes do sistema
  (New York e SF). Para gerar de novo, dentro de `fonte/`:

      swiftc -O base.swift main.swift -o fita && ./fita

Cores e tipos são os da v4 (`Edicao.swift`): cada cor com um papel só.
