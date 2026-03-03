/// サービスを ID で登録・取得・フィルタリングするレジストリ。
public actor TranscriberRegistry {
    private var services: [String: any TranscriptionService] = [:]

    public init() {}

    /// サービスを登録する。同一 ID は上書きされる。
    public func register(_ service: any TranscriptionService) {
        services[service.id] = service
    }

    /// 指定 ID のサービスを返す。未登録なら nil。
    public func service(for id: String) -> (any TranscriptionService)? {
        services[id]
    }

    /// 現在 isAvailable == true のサービス一覧を返す。
    /// await 中の actor 再入による Dictionary 変更を防ぐためスナップショットで反復する。
    public func availableServices() async -> [any TranscriptionService] {
        let snapshot = Array(services.values)
        var result: [any TranscriptionService] = []
        result.reserveCapacity(snapshot.count)
        for svc in snapshot {
            if await svc.isAvailable { result.append(svc) }
        }
        return result
    }
}
