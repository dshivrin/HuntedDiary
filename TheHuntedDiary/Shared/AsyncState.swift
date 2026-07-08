import Foundation

enum AsyncState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(Error)
}
