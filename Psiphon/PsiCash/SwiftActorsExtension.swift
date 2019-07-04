//
//  SwiftActorsExtension.swift
//  Psiphon
//
//  Created by Amir Khan on 2019-07-03.
//  Copyright © 2019 Psiphon Inc. All rights reserved.
//

import Foundation
import SwiftActors

public typealias Processor = (AnyMessage) throws -> Receive
