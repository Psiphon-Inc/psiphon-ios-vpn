/*
 * Copyright (c) 2019, Psiphon Inc.
 * All rights reserved.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

import Foundation
import RxSwift
import Promises

extension ObservableType {

    // TODO:: Write a test for this
    func falseIfNotTrueWithin(_ timeout: DispatchTimeInterval,
                              _ transform: @escaping (Self.Element) -> Bool) -> Single<Bool> {
        
        self.map { transform($0) }
            .filter { $0 == true }
            .take(1)
            .timeout(timeout, scheduler: MainScheduler.instance)
            .catchErrorJustReturn(false)
            .asSingle()
    }

}

/// TODO: this is ideally an extension on 
extension ObservableType where Element: ExpressibleByNilLiteral {

    /// Same as `take(1).asSingle()`
    /// Returns current state of the observable.
    func currentState() -> Single<Element> {
        self.take(1).asSingle()
    }

}

extension ObservableType {

    /// This is a simple but very inefficient implementation of mapAsync.
    func mapAsync<Result>(_ transform: @escaping (Element) throws -> Promise<Result>)
        -> Observable<Result> {

            self.flatMap { element -> Observable<Result> in

                Observable.create { observer -> Disposable in

                    let disposable = BooleanDisposable()

                    try! transform(element).then { result in
                        guard disposable.isDisposed == false else {
                            return
                        }
                        observer.on(.next(result))
                        observer.on(.completed)
                    }
                    .catch { error in
                        guard disposable.isDisposed == false else {
                            return
                        }
                        observer.on(.error(error))
                    }

                    return disposable
                }
            }
    }

}

extension PrimitiveSequenceType where Self.Trait == RxSwift.SingleTrait {

    // Fix: duplicated implementation of `mapAsync` for ObservableType
    func mapAsync<Result>(_ transform: @escaping (Element) throws -> Promise<Result>)
           -> Single<Result> {

            self.flatMap { element -> Single<Result> in
                return Single<Result>.create { (observer: @escaping (SingleEvent<Result>) -> Void) -> Disposable in

                    let disposable = BooleanDisposable()

                    try! transform(element).then { result in
                        guard disposable.isDisposed == false else {
                            return
                        }
                        observer(.success(result))
                    }
                    .catch { error in
                        guard disposable.isDisposed == false else {
                            return
                        }
                        observer(.error(error))
                    }

                    return disposable
                }
            }

       }
}
