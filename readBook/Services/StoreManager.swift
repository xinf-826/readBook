//
//  StoreManager.swift
//  readBook
//
//  StoreKit2 封装（架构预留）。当前为 Stub 空实现，不接入实际支付。
//  后续接入时：配置 productIdentifiers、在 App 启动调用 start()/loadProducts()，
//  并补全 purchase / restore / 交易校验逻辑。
//

import StoreKit
import Observation

enum StoreError: Error, LocalizedError {
    /// 尚未接入实际支付。
    case notImplemented
    /// 交易校验失败。
    case failedVerification

    var errorDescription: String? {
        switch self {
        case .notImplemented: "支付功能尚未开放"
        case .failedVerification: "交易校验失败"
        }
    }
}

@Observable
final class StoreManager {
    static let shared = StoreManager()

    /// 待上架的商品 ID，接入时配置。
    var productIdentifiers: [String] = []

    /// 已加载的商品。
    private(set) var products: [Product] = []
    /// 已购买/已解锁的商品 ID。
    private(set) var purchasedProductIDs: Set<String> = []

    @ObservationIgnored private var transactionListener: Task<Void, Never>?

    private init() {}

    // MARK: - 生命周期

    /// 启动交易监听（App 启动时调用）。
    func start() {
        transactionListener?.cancel()
        transactionListener = listenForTransactions()
    }

    func stop() {
        transactionListener?.cancel()
        transactionListener = nil
    }

    // MARK: - 商品获取

    /// 拉取商品。Stub：未配置商品 ID 时返回空，接入后走 StoreKit 真实请求。
    @MainActor
    func loadProducts() async {
        guard !productIdentifiers.isEmpty else {
            products = []
            return
        }
        do {
            products = try await Product.products(for: productIdentifiers)
        } catch {
            print("[StoreManager] 商品加载失败: \(error)")
            products = []
        }
    }

    // MARK: - 购买 / 恢复

    /// 购买商品。Stub：暂未接入实际支付。
    @discardableResult
    func purchase(_ product: Product) async throws -> Transaction? {
        throw StoreError.notImplemented
    }

    /// 恢复购买。Stub：接入后调用 `try? await AppStore.sync()` 并刷新权益。
    func restorePurchases() async {
        // try? await AppStore.sync()
        await updatePurchasedProducts()
    }

    /// 查询某商品是否已解锁。
    func isPurchased(_ productID: String) -> Bool {
        purchasedProductIDs.contains(productID)
    }

    // MARK: - 交易校验

    /// 校验交易签名。接入后用于所有交易的验真。
    func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    /// 刷新当前已解锁权益。Stub：接入后遍历 `Transaction.currentEntitlements`。
    @MainActor
    func updatePurchasedProducts() async {
        // for await result in Transaction.currentEntitlements {
        //     guard let transaction = try? checkVerified(result) else { continue }
        //     if transaction.revocationDate == nil {
        //         purchasedProductIDs.insert(transaction.productID)
        //     } else {
        //         purchasedProductIDs.remove(transaction.productID)
        //     }
        // }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            // Stub：接入后监听 Transaction.updates，校验并发放权益。
            // for await update in Transaction.updates {
            //     guard let self, let transaction = try? self.checkVerified(update) else { continue }
            //     await self.updatePurchasedProducts()
            //     await transaction.finish()
            // }
            _ = self
        }
    }
}
