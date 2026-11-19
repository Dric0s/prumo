import Foundation

/// Hash FNV-1a de 64 bits. Determinístico entre processos, versões do Swift e plataformas
/// (ao contrário de `Hasher`, que usa semente aleatória por execução).
enum HashEstavel {
    static func fnv1a(_ partes: [String]) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for parte in partes {
            for byte in parte.utf8 {
                hash ^= UInt64(byte)
                hash &*= 0x0000_0100_0000_01b3
            }
            // Separador para que ["ab","c"] e ["a","bc"] não colidam.
            hash ^= 0xff
            hash &*= 0x0000_0100_0000_01b3
        }
        return hash
    }
}

/// Gerador SplitMix64: pequeno, rápido e com sequência fixa para a mesma semente.
struct SplitMix64 {
    private var estado: UInt64

    init(semente: UInt64) { estado = semente }

    mutating func proximo() -> UInt64 {
        estado &+= 0x9e37_79b9_7f4a_7c15
        var z = estado
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }
}

extension Array {
    /// Fisher–Yates com gerador próprio. Não usa `shuffled(using:)` porque a
    /// biblioteca padrão não garante o mesmo algoritmo entre versões.
    func embaralhadoEstavel(semente: UInt64) -> [Element] {
        var copia = self
        guard copia.count > 1 else { return copia }
        var gerador = SplitMix64(semente: semente)
        for i in stride(from: copia.count - 1, to: 0, by: -1) {
            let j = Int(gerador.proximo() % UInt64(i + 1))
            copia.swapAt(i, j)
        }
        return copia
    }
}
