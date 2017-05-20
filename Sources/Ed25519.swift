//
//  Ed25519.swift
//  Ed25519
//
//  Created by pebble8888 on 2017/05/13.
//  Copyright © 2017年 pebble8888. All rights reserved.
//

import Foundation
import CommonCrypto
import BigInt

public struct Ed25519 {
    
    static let b:Int = 256
    static let q:BigInt = BigInt(2).power(255) - 19
    static let l:BigInt = BigInt(2).power(252) + BigInt("27742317777372353535851937790883648493")!
    static func H(_ m:[UInt8]) -> [UInt8] {
        return sha512(m).digest()
    }
    
    // return val is less than m
    static func expmod(_ b:BigInt, _ e:BigInt, _ m:BigInt) -> BigInt {
        if e == 0 { return 1 }
        var t = expmod(b, e.divide(2), m).power(2).modulo(m)
        if e.parity() != 0 {
            t = (t*b).modulo(m)
        }
        return t
    }
    
    // return val is less than q
    static func inv(_ x:BigInt) -> BigInt {
        return expmod(x,q-2,q)
    }
    
    static let d:BigInt = BigInt(-121665) * inv(BigInt(121666)) 
    // return val is less than q
    static let I:BigInt = expmod(2, (q-1).divide(4), q)
    
    static func xrecover(_ y:BigInt) -> BigInt {
        let xx = (y*y-1) * inv(d*y*y+1)
        var x = expmod(xx,(q+3).divide(8),q)
        if (x*x - xx).modulo(q) != 0 {
            x = (x*I).modulo(q) 
        }
        if x.modulo(2) != 0 {
            x = q-x
        }
        return x
    }
    
    static let By:BigInt = 4 * inv(5)
    static let Bx:BigInt = xrecover(By)
    static let B:[BigInt] = [Bx.modulo(q), By.modulo(q)]  
    
    static func edwards(_ P:[BigInt], _ Q:[BigInt]) -> [BigInt] {
        let x1 = P[0]
        let y1 = P[1]
        let x2 = Q[0]
        let y2 = Q[1]
        let x3 = (x1*y2+x2*y1) * inv(1+d*x1*x2*y1*y2)
        let y3 = (y1*y2+x1*x2) * inv(1-d*x1*x2*y1*y2)
        return [x3.modulo(q), y3.modulo(q)]
    }
    
    static func scalarmult(_ P:[BigInt], _ e:BigInt) -> [BigInt] {
        if e == 0 {
            return [0, 1]
        }
        var Q = scalarmult(P, e.divide(2))
        Q = edwards(Q, Q)
        if e.parity() != 0 {
            Q = edwards(Q, P)
        }
        return Q
    }

    static func encodeint(_ y:BigInt) -> [UInt8] {
        var bits:[Int] = []
        for i in 0 ..< b {
            bits.append((y.abs >> i).parity())
        }
        var s:[UInt8] = []
        for i in 0 ..< b/8 {
            s.append(UInt8( (0..<8).map({ bits[i*8 + $0] << $0 }).sum() ))
        }
        return s
    }
    
    static func encodepoint(_ P:[BigInt]) -> [UInt8] {
        let x = P[0]
        let y = P[1]
        var bits:[Int] = []
        for i in 0 ..< b-1 {
            bits.append((y.abs >> i).parity())
        }
        bits.append(x.parity())
        var s:[UInt8] = [] 
        for i in 0 ..< b/8 {
            s.append(UInt8( (0..<8).map({ bits[i*8 + $0] << $0 }).sum() ))
        }
        return s
    }
    
    static func bit(_ h:[UInt8], _ i:Int) -> BigInt {
        return BigInt((h[i/8] >> UInt8(i%8)) & 1)
    }
    
    public static func publickey(_ sk:[UInt8] ) -> [UInt8] {
        let h:[UInt8] = H(sk)
        let a:BigInt = BigInt(2).power(b-2) + (3..<b-2).map({BigInt(2).power($0) * bit(h, $0)}).sum()
        let A = scalarmult(B, a)
        return encodepoint(A)
    }
    
    static func Hint(_ m:[UInt8]) -> BigInt {
        let h:[UInt8] = H(m)
        return (0..<2*b).map({BigInt(2).power($0) * bit(h, $0)}).sum()
    }
    
    public static func signature(_ m:[UInt8] , _ sk:[UInt8], _ pk:[UInt8]) -> [UInt8] {
        let h:[UInt8] = H(sk)
        let a = BigInt(2).power(b-2) + (3..<b-2).map({BigInt(2).power($0) * bit(h, $0)}).sum() 
        var s:[UInt8] = [] 
        for i in b/8 ..< b/4 {
            s.append(h[i])
        }
        let r = Hint(s+m)
        let R = scalarmult(B,r)
        let S = (r + Hint(encodepoint(R) + pk + m) * a).modulo(l)
        return encodepoint(R) + encodeint(S)
    }
    
    static func isoncurve(_ P:[BigInt]) -> Bool {
        let x = P[0]
        let y = P[1]
        let z1 = -x*x
        let z2 = y*y 
        let z3 = BigInt(-1)
        let z4 = -d*x*x*y*y
        let z10 = (z1 + z2 + z3 + z4).modulo(q)
        return z10 == 0
    }
    
    static func decodeint(_ s:[UInt8]) -> BigInt {
        return (0..<b).map({ BigInt(2).power($0) * bit(s,$0)}).sum()
    }
    
    static func decodepoint(_ s:[UInt8]) -> [BigInt] {
        let y = (0..<b-1).map({BigInt(2).power($0) * bit(s, $0)}).sum()
        var x = xrecover(y)
        if BigInt(x.parity()) != bit(s, b-1) {
            x = q-x
        }
        let P = [x,y]
        if !isoncurve(P) {
            fatalError("decoding point that is not on curve")
        }
        return P
    }
    
    public static func checkvalid(_ s:[UInt8], _ m:[UInt8], _ pk:[UInt8]) -> Bool {
        if s.count != b/4 {
            // signature length is wrong
            return false
        }
        if pk.count != b/8 {
            // public-key length is wrong
            return false
        }
        let R = decodepoint(Array(s[0..<b/8]))
        let A = decodepoint(pk)
        let S = decodeint(Array(s[b/8..<b/4]))
        let h = Hint(encodepoint(R) + pk + m)
        if scalarmult(B, S) != edwards(R, scalarmult(A, h)) {
            // Signature does not pass verification
            return false
        }
        return true
    }
    
    struct Digest {
        var data:[UInt8]
        var length:Int
        func digest() -> [UInt8] {
            return data
        }
        func hexdiegst() -> String {
            return data.map({ String(format: "%02x", $0) }).joined()
        }
    }
    
}

protocol Summable {
    static var Zero: Self { get }
    static func +(lhs: Self, rhs: Self) -> Self
}

extension Sequence where Iterator.Element: Summable {
    func sum() -> Iterator.Element {
        return self.reduce(Iterator.Element.Zero, +)
    }
}

extension Int: Summable {
    static var Zero: Int { return 0 }
}

extension BigInt: Summable {
    static var Zero: BigInt { return BigInt(0) }
}

extension String {
    public func unhexlify() -> [UInt8] {
        var pos = startIndex
        return (0..<characters.count/2).flatMap { _ in
            defer { pos = index(pos, offsetBy: 2) }
            return UInt8(self[pos...index(after: pos)], radix: 16)
        }
    }
}

extension Collection where Iterator.Element == UInt8 {
    public func hexDescription() -> String {
        return self.map({ String(format: "%02x", $0) }).joined()
    }
}


func sha512(_ s:[UInt8]) -> Ed25519.Digest {
    let data = Data(bytes:s)
    var digest = [UInt8](repeating: 0, count: Int(CC_SHA512_DIGEST_LENGTH))
    data.withUnsafeBytes({
        _ = CC_SHA512($0, CC_LONG(data.count), &digest)
    })
    return Ed25519.Digest(data: digest, length: Int(CC_SHA512_DIGEST_LENGTH))
}
