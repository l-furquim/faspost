import Foundation

struct KeyValueRow: Identifiable, Equatable, Hashable {
    var id: UUID
    var key: String
    var value: String
    var isEnabled: Bool

    init(id: UUID = UUID(), key: String = "", value: String = "", isEnabled: Bool = true) {
        self.id = id
        self.key = key
        self.value = value
        self.isEnabled = isEnabled
    }

    init(_ header: HTTPHeader) {
        self.init(key: header.key, value: header.value, isEnabled: header.disabled != true)
    }

    init(_ param: QueryParam) {
        self.init(key: param.key, value: param.value ?? "", isEnabled: param.disabled != true)
    }

    var header: HTTPHeader {
        HTTPHeader(key: key, value: value, disabled: isEnabled ? nil : true)
    }

    var queryParam: QueryParam {
        QueryParam(key: key, value: value, disabled: isEnabled ? nil : true)
    }
}
