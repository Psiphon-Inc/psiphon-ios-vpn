import XCTest

import PsiApiTests

var tests = [XCTestCaseEntry]()
tests += PsiApiTests.allTests()
XCTMain(tests)
