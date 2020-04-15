import PlaygroundSupport
import UIKit
import PsiphonPlayground


func test() {
    let a: Either<String, Int>
    a = .left("Hello, playground")

    var b: PredicatedValue<String, ()>
    b = .init(value: "hi", predicate: {_ in true})
    b = b.map { msg in
        msg + " something extra"
    }

    print(a)
    print(b.getValue(())!)

}


test()
