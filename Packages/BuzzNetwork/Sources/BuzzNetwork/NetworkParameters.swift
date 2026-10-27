import CryptoKit
import Foundation
import Network
import Security

/// The protocol stack every BuzzLight connection uses (TN3213's recommendation for local play):
/// WebSocket (message boundaries) over TLS-PSK (encryption without certificates) over TCP
/// (no Nagle delay, keepalive), with peer-to-peer Wi-Fi allowed so phones that are not on the
/// same network can still connect directly.
enum NetworkParameters {
    /// TLS-PSK identity and key. The key is derived from a constant that ships in the app, so it
    /// keeps frames private from anything that is not BuzzLight but does not authenticate players
    /// (ADR 0007). Changing either value makes old and new builds unable to connect.
    static let pskIdentity = Data("buzzlight".utf8)
    static let presharedKey: Data = Data(SHA256.hash(data: Data("buzzlight-local-play-v1".utf8)))

    static func make() -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let key = presharedKey.withUnsafeBytes { DispatchData(bytes: $0) }
        let identity = pskIdentity.withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(tls.securityProtocolOptions, key as __DispatchData, identity as __DispatchData)
        sec_protocol_options_append_tls_ciphersuite(
            tls.securityProtocolOptions,
            tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!
        )

        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true            // small frames go out immediately: buzz timing matters
        // Last-resort dead-peer detection (~30 s). The sessions' 1 s heartbeat normally decides
        // first (10–12 s of silence). The old 5 s + 3×2 s setting killed peer-to-peer links during
        // ordinary stalls, on both phones at once.
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 10
        tcp.keepaliveInterval = 5
        tcp.keepaliveCount = 4

        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.includePeerToPeer = true

        let webSocket = NWProtocolWebSocket.Options()
        webSocket.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(webSocket, at: 0)
        return parameters
    }

    /// A binary WebSocket frame: one `GameMessageCodec` envelope per message.
    static let frameContext = NWConnection.ContentContext(
        identifier: "frame",
        metadata: [NWProtocolWebSocket.Metadata(opcode: .binary)]
    )
}
