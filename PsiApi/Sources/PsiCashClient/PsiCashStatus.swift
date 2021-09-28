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

/// Defines PsiCashStatusInvalid type for PsiCash library "invalid" status code.
public protocol PsiCashStatusInvalid: PsiCashErrorStatusProtocol {
    static var invalid: Self { get }
}

/// Defines PsiCashStatusExistingTransaction type for PsiCash library "ExistingTransaction" status code.
public protocol PsiCashStatusExistingTransaction: PsiCashErrorStatusProtocol {
    static var existingTransaction: Self { get }
}

/// Defines PsiCashStatusInsufficientBalance type for PsiCash library "InsufficientBalance" status code.
public protocol PsiCashStatusInsufficientBalance: PsiCashErrorStatusProtocol {
    static var insufficientBalance: Self { get }
}

/// Defines PsiCashStatusTransactionAmountMismatch type for PsiCash library "TransactionAmountMismatch" status code.
public protocol PsiCashStatusTransactionAmountMismatch: PsiCashErrorStatusProtocol {
    static var transactionAmountMismatch: Self { get }
}

/// Defines PsiCashStatusTransactionTypeNotFound type for PsiCash library "TransactionAmountMismatch" status code.
public protocol PsiCashStatusTransactionTypeNotFound: PsiCashErrorStatusProtocol {
    static var transactionTypeNotFound: Self { get }
}

/// Defines PsiCashStatusInvalidTokens type for PsiCash library "InvalidTokens" status code.
public protocol PsiCashStatusInvalidTokens: PsiCashErrorStatusProtocol {
    static var invalidTokens: Self { get }
}

/// Defines PsiCashStatusInvalidCredentials for PsiCash library "InvalidCredentials" status code.
public protocol PsiCashStatusInvalidCredentials: PsiCashErrorStatusProtocol {
    static var invalidCredentials: Self { get }
}

/// Defines PsiCashStatusBadRequest type for PsiCash library "BadRequest" status code.
public protocol PsiCashStatusBadRequest: PsiCashErrorStatusProtocol {
    static var badRequest: Self { get }
}

/// Defines PsiCashStatusServerError type for PsiCash library "Server" status code.
public protocol PsiCashStatusServerError: PsiCashErrorStatusProtocol {
    static var serverError: Self { get }
}

/// Represents set of possible error status codes from PsiCash library for refresh state action.
public enum PsiCashRefreshErrorStatus:
    PsiCashStatusServerError
    , PsiCashStatusInvalidTokens {
        
    case serverError
    
    case invalidTokens
    
}

/// Represents set of possible error status codes from PsiCash library for a "expiring-purchase" transaction class.
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

/// Represents set of possible error status codes from the PsiCash library for account login.
public enum PsiCashAccountLoginErrorStatus:
    PsiCashStatusInvalidCredentials
    , PsiCashStatusBadRequest
    , PsiCashStatusServerError {
        
    case invalidCredentials
    
    case badRequest
    
    case serverError
    
}
