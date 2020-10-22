/*
 * Copyright (c) 2020, Psiphon Inc.
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

import enum Utilities.Unit
import typealias PsiApi.HashableError

/// Represents a PsiCash client lib status value.
public protocol PsiCashErrorStatusProtocol: HashableError {}

public protocol PsiCashStatusInvalid: PsiCashErrorStatusProtocol {
    static var invalid: Self { get }
}

public protocol PsiCashStatusExistingTransaction: PsiCashErrorStatusProtocol {
    static var existingTransaction: Self { get }
}

public protocol PsiCashStatusInsufficientBalance: PsiCashErrorStatusProtocol {
    static var insufficientBalance: Self { get }
}

public protocol PsiCashStatusTransactionAmountMismatch: PsiCashErrorStatusProtocol {
    static var transactionAmountMismatch: Self { get }
}

public protocol PsiCashStatusTransactionTypeNotFound: PsiCashErrorStatusProtocol {
    static var transactionTypeNotFound: Self { get }
}

public protocol PsiCashStatusInvalidTokens: PsiCashErrorStatusProtocol {
    static var invalidTokens: Self { get }
}

public protocol PsiCashStatusInvalidCredentials: PsiCashErrorStatusProtocol {
    static var invalidCredentials: Self { get }
}

public protocol PsiCashStatusBadRequest: PsiCashErrorStatusProtocol {
    static var badRequest: Self { get }
}

public protocol PsiCashStatusServerError: PsiCashErrorStatusProtocol {
    static var serverError: Self { get }
}

public enum PsiCashRefreshErrorStatus:
    PsiCashStatusServerError
    , PsiCashStatusInvalidTokens {
        
    case serverError
    
    case invalidTokens
    
}

public enum PsiCashNewExpiringPurchaseErrorStatus:
    PsiCashStatusExistingTransaction
    , PsiCashStatusInsufficientBalance
    , PsiCashStatusTransactionAmountMismatch
    , PsiCashStatusTransactionTypeNotFound
    , PsiCashStatusInvalidTokens
    , PsiCashStatusServerError {
        
    case existingTransaction
    
    case insufficientBalance
    
    case transactionAmountMismatch
    
    case transactionTypeNotFound
    
    case invalidTokens
    
    case serverError
    
}

public enum PsiCashAccountLoginErrorStatus:
    PsiCashStatusInvalidCredentials
    , PsiCashStatusBadRequest
    , PsiCashStatusServerError {
        
    case invalidCredentials
    
    case badRequest
    
    case serverError
    
}
