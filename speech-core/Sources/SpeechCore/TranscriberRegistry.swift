/// サービスを ID で登録・取得・フィルタリングするレジストリ。
/// 登録順を保持し、availableServices() は登録順で返す。
public actor TranscriberRegistry {
    private var orderedIds: [String] = []
    private var services: [String: any TranscriptionService] = [:]

    public init() {}

    /// サービスを登録する。同一 ID は上書き（登録順は維持）。
    public func register(_ service: any TranscriptionService) {
        if services[service.id] == nil {
            orderedIds.append(service.id)
        }
        services[service.id] = service
    }

    /// 指定 ID のサービスを返す。未登録なら nil。
    public func service(for id: String) -> (any TranscriptionService)? {
        services[id]
    }

    /// 現在 isAvailable == true のサービス一覧を登録順で返す。
    public func availableServices() async -> [any TranscriptionService] {
        var result: [any TranscriptionService] = []
        result.reserveCapacity(orderedIds.count)
        for id in orderedIds {
            if let svc = services[id], await svc.isAvailable {
                result.append(svc)
            }
        }
        return result
    }

    /// 設定の selectedTranscriptionServiceId に基づいてサービスを解決する。
    /// - preferredId が指定されており、そのサービスが利用可能ならそれを返す。
    /// - それ以外は登録順で最初の利用可能サービスにフォールバックする。
    public func resolveService(preferredId: String?) async -> (any TranscriptionService)? {
        if let preferredId, let svc = services[preferredId], await svc.isAvailable {
            return svc
        }
        return await availableServices().first
    }
}
