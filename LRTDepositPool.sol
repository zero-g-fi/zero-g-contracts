// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.21;

import { UtilLib } from "./utils/UtilLib.sol";
import { LRTConstants } from "./utils/LRTConstants.sol";

import { LRTConfigRoleChecker, ILRTConfig } from "./utils/LRTConfigRoleChecker.sol";
import { IZgETH } from "./interfaces/IZgETH.sol";
import { ILRTOracle } from "./interfaces/ILRTOracle.sol";
import { INodeDelegator } from "./interfaces/INodeDelegator.sol";
import { ILRTDepositPool } from "./interfaces/ILRTDepositPool.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/// @title LRTDepositPool - Deposit Pool Contract for LSTs
/// @notice Handles LST asset deposits
contract LRTDepositPool is ILRTDepositPool, LRTConfigRoleChecker, PausableUpgradeable, ReentrancyGuardUpgradeable {
    uint256 public maxNodeDelegatorLimit;
    uint256 public minAmountToDeposit;

    mapping(address => uint256) public isNodeDelegator; // 0: not a node delegator, 1: is a node delegator
    address[] public nodeDelegatorQueue;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the contract
    /// @param lrtConfigAddr LRT config address
    function initialize(address lrtConfigAddr) external initializer {
        UtilLib.checkNonZeroAddress(lrtConfigAddr);
        __Pausable_init();
        __ReentrancyGuard_init();
        maxNodeDelegatorLimit = 10;
        lrtConfig = ILRTConfig(lrtConfigAddr);
        emit UpdatedLRTConfig(lrtConfigAddr);
    }

    /*//////////////////////////////////////////////////////////////
                            view functions
    //////////////////////////////////////////////////////////////*/

    /// @notice gets the total asset present in protocol
    /// @param asset Asset address
    /// @return totalAssetDeposit total asset present in protocol
    function getTotalAssetDeposits(address asset) public view override returns (uint256 totalAssetDeposit) {
        (uint256 assetLyingInDepositPool, uint256 assetLyingInNDCs, uint256 assetStakedInEigenLayer) =
            getAssetDistributionData(asset);
        return (assetLyingInDepositPool + assetLyingInNDCs + assetStakedInEigenLayer);
    }

    /// @notice gets the current limit of asset deposit
    /// @param asset Asset address
    /// @return currentLimit Current limit of asset deposit
    function getAssetCurrentLimit(address asset) public view override returns (uint256) {
        if (getTotalAssetDeposits(asset) > lrtConfig.depositLimitByAsset(asset)) {
            return 0;
        }

        return lrtConfig.depositLimitByAsset(asset) - getTotalAssetDeposits(asset);
    }

    /// @dev get node delegator queue
    /// @return nodeDelegatorQueue Array of node delegator contract addresses
    function getNodeDelegatorQueue() external view override returns (address[] memory) {
        return nodeDelegatorQueue;
    }

    /// @dev provides asset amount distribution data among depositPool, NDCs and eigenLayer
    /// @param asset the asset to get the total amount of
    /// @return assetLyingInDepositPool asset amount lying in this LRTDepositPool contract
    /// @return assetLyingInNDCs asset amount sum lying in all NDC contract
    /// @return assetStakedInEigenLayer asset amount deposited in eigen layer strategies through all NDCs
    function getAssetDistributionData(address asset)
        public
        view
        override
        onlySupportedAsset(asset)
        returns (uint256 assetLyingInDepositPool, uint256 assetLyingInNDCs, uint256 assetStakedInEigenLayer)
    {
        if (asset == LRTConstants.ETH_TOKEN) {
            return getETHDistributionData();
        }
        assetLyingInDepositPool = IERC20(asset).balanceOf(address(this));

        uint256 ndcsCount = nodeDelegatorQueue.length;
        for (uint256 i; i < ndcsCount;) {
            assetLyingInNDCs += IERC20(asset).balanceOf(nodeDelegatorQueue[i]);
            assetStakedInEigenLayer += INodeDelegator(nodeDelegatorQueue[i]).getAssetBalance(asset);
            unchecked {
                ++i;
            }
        }
    }

    /// @dev provides ETH amount distribution data among depositPool, NDCs and eigenLayer
    function getETHDistributionData()
        public
        view
        override
        returns (uint256 ethLyingInDepositPool, uint256 ethLyingInNDCs, uint256 ethStakedInEigenLayer)
    {
        ethLyingInDepositPool = address(this).balance;

        uint256 ndcsCount = nodeDelegatorQueue.length;
        for (uint256 i; i < ndcsCount;) {
            ethLyingInNDCs += nodeDelegatorQueue[i].balance;
            ethStakedInEigenLayer += INodeDelegator(nodeDelegatorQueue[i]).getETHEigenPodBalance();
            unchecked {
                ++i;
            }
        }
    }

    /// @notice View amount of zgETH to mint for given asset amount
    /// @param asset Asset address
    /// @param amount Asset amount
    /// @return zgEthAmount Amount of zgETH to mint
    function getMintAmount(address asset, uint256 amount) public view override returns (uint256 zgEthAmount) {
        // setup oracle contract
        address lrtOracleAddress = lrtConfig.getContract(LRTConstants.LRT_ORACLE);
        ILRTOracle lrtOracle = ILRTOracle(lrtOracleAddress);

        // calculate zgETH amount to mint based on asset amount and asset exchange rate
        zgEthAmount = (amount * lrtOracle.getAssetPrice(asset)) / lrtOracle.zgETHPrice();
    }

    /*//////////////////////////////////////////////////////////////
                            write functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Allows user to deposit ETH to the protocol
    /// @param minZgETHAmountExpected Minimum amount of zgETH to receive
    /// @param referralId referral id
    function depositETH(
        uint256 minZgETHAmountExpected,
        string calldata referralId
    )
        external
        payable
        whenNotPaused
        nonReentrant
    {
        // checks
        uint256 zgETHAmount = _beforeDeposit(LRTConstants.ETH_TOKEN, msg.value, minZgETHAmountExpected);

        // interactions
        _mint(zgETHAmount);

        emit ETHDeposit(msg.sender, msg.value, zgETHAmount, referralId);
    }

    /// @notice helps user stake LST to the protocol
    /// @param asset LST asset address to stake
    /// @param depositAmount LST asset amount to stake
    /// @param minZgETH Minimum amount of zgETH to receive
    function depositAsset(
        address asset,
        uint256 depositAmount,
        uint256 minZgETH,
        string calldata referralId
    )
        external
        whenNotPaused
        nonReentrant
        onlySupportedAsset(asset)
    {
        // checks
        uint256 zgETHAmount = _beforeDeposit(asset, depositAmount, minZgETH);

        // interactions
        if (!IERC20(asset).transferFrom(msg.sender, address(this), depositAmount)) {
            revert TokenTransferFailed();
        }
        _mint(zgETHAmount);

        emit AssetDeposit(msg.sender, asset, depositAmount, zgETHAmount, referralId);
    }

    function _beforeDeposit(
        address asset,
        uint256 depositAmount,
        uint256 minZgETH
    )
        private
        view
        returns (uint256 zgETHAmount)
    {
        if (depositAmount == 0 || depositAmount < minAmountToDeposit) {
            revert InvalidAmountToDeposit();
        }

        if (depositAmount > getAssetCurrentLimit(asset)) {
            revert MaximumDepositLimitReached();
        }
        zgETHAmount = getMintAmount(asset, depositAmount);

        if (zgETHAmount < minZgETH) {
            revert MinimumAmountToReceiveNotMet();
        }
    }

    /// @dev private function to mint zgETH
    /// @param zgEthAmount Amount of zgETH minted
    function _mint(uint256 zgEthAmount) private {
        address zgETH = lrtConfig.zgETH();
        // mint zgETH for user
        IZgETH(zgETH).mint(msg.sender, zgEthAmount);
    }

    /// @notice add new node delegator contract addresses
    /// @dev only callable by LRT admin
    /// @param nodeDelegatorContracts Array of NodeDelegator contract addresses
    function addNodeDelegatorContractToQueue(address[] calldata nodeDelegatorContracts) external onlyLRTAdmin {
        uint256 length = nodeDelegatorContracts.length;
        if (nodeDelegatorQueue.length + length > maxNodeDelegatorLimit) {
            revert MaximumNodeDelegatorLimitReached();
        }

        for (uint256 i; i < length;) {
            UtilLib.checkNonZeroAddress(nodeDelegatorContracts[i]);

            // check if node delegator contract is already added and add it if not
            if (isNodeDelegator[nodeDelegatorContracts[i]] == 0) {
                nodeDelegatorQueue.push(nodeDelegatorContracts[i]);
            }

            isNodeDelegator[nodeDelegatorContracts[i]] = 1;

            unchecked {
                ++i;
            }
        }

        emit NodeDelegatorAddedInQueue(nodeDelegatorContracts);
    }

    /// @notice remove node delegator contract address from queue
    /// @dev only callable by LRT admin
    /// @param nodeDelegatorAddress NodeDelegator contract address
    function removeNodeDelegatorContractFromQueue(address nodeDelegatorAddress) public onlyLRTAdmin {
        //  revert if node delegator contract has ETH in it or it has ETH in eigenpod
        if (
            INodeDelegator(nodeDelegatorAddress).getETHEigenPodBalance() > 0
                || address(nodeDelegatorAddress).balance > 0
        ) {
            revert NodeDelegatorHasETH();
        }

        // revert if node delegator contract has assets lying in it or it has asset in eigenlayer asset strategies
        (address[] memory assets, uint256[] memory assetBalances) =
            INodeDelegator(nodeDelegatorAddress).getAssetBalances();

        uint256 assetsLength = assets.length;
        for (uint256 i; i < assetsLength;) {
            if (assetBalances[i] > 0) {
                revert NodeDelegatorHasAssetBalance(assets[i], assetBalances[i]);
            }

            if (IERC20(assets[i]).balanceOf(nodeDelegatorAddress) > 0) {
                revert NodeDelegatorHasAssetBalance(assets[i], IERC20(assets[i]).balanceOf(nodeDelegatorAddress));
            }

            unchecked {
                ++i;
            }
        }

        uint256 length = nodeDelegatorQueue.length;
        uint256 ndcIndex;

        for (uint256 i; i < length;) {
            if (nodeDelegatorQueue[i] == nodeDelegatorAddress) {
                ndcIndex = i;
                break;
            }

            if (i == length - 1) {
                revert NodeDelegatorNotFound();
            }

            unchecked {
                ++i;
            }
        }

        // remove node delegator contract from queue
        nodeDelegatorQueue[ndcIndex] = nodeDelegatorQueue[length - 1];
        nodeDelegatorQueue.pop();

        emit NodeDelegatorRemovedFromQueue(nodeDelegatorAddress);
    }

    /// @notice remove many node delegator contracts from queue
    /// @dev calls internally removeNodeDelegatorContractFromQueue which is only callable by LRT admin
    /// @param nodeDelegatorContracts Array of NodeDelegator contract addresses
    function removeManyNodeDelegatorContractsFromQueue(address[] calldata nodeDelegatorContracts)
        external
        onlyLRTAdmin
    {
        uint256 length = nodeDelegatorContracts.length;

        for (uint256 i; i < length;) {
            removeNodeDelegatorContractFromQueue(nodeDelegatorContracts[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice transfers asset lying in this DepositPool to node delegator contract
    /// @dev only callable by LRT manager
    /// @param ndcIndex Index of NodeDelegator contract address in nodeDelegatorQueue
    /// @param asset Asset address
    /// @param amount Asset amount to transfer
    function transferAssetToNodeDelegator(
        uint256 ndcIndex,
        address asset,
        uint256 amount
    )
        external
        nonReentrant
        onlyLRTOperator
        onlySupportedAsset(asset)
    {
        address nodeDelegator = nodeDelegatorQueue[ndcIndex];
        UtilLib.checkNonZeroAddress(nodeDelegator);

        if (!IERC20(asset).transfer(nodeDelegator, amount)) {
            revert TokenTransferFailed();
        }
    }

    /// @notice Transfers all specified assets lying in this DepositPool to a node delegator
    /// @dev only callable by LRT Manager
    /// @param ndcIndex Index of NodeDelegator contract address in nodeDelegatorQueue starting at zero.
    /// @param assets List of asset addresses
    function transferAssetsToNodeDelegator(
        uint256 ndcIndex,
        address[] calldata assets
    )
        external
        override
        nonReentrant
        onlyLRTOperator
    {
        address nodeDelegator = nodeDelegatorQueue[ndcIndex];
        UtilLib.checkNonZeroAddress(nodeDelegator);

        // For each of the specified assets
        for (uint256 i; i < assets.length;) {
            // Check the asset is supported
            if (!lrtConfig.isSupportedAsset(assets[i])) {
                revert ILRTConfig.AssetNotSupported();
            }

            // Get the asset's balance held by this contract
            uint256 amount = IERC20(assets[i]).balanceOf(address(this));

            // If something to transfer
            if (amount > 0) {
                // Transfer the asset to the node delegator
                if (!IERC20(assets[i]).transfer(nodeDelegator, amount)) {
                    revert TokenTransferFailed();
                }
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @notice transfers ETH lying in this DepositPool to node delegator contract
    /// @dev only callable by LRT manager
    /// @param ndcIndex Index of NodeDelegator contract address in nodeDelegatorQueue
    /// @param amount ETH amount to transfer
    function transferETHToNodeDelegator(uint256 ndcIndex, uint256 amount) external nonReentrant onlyLRTOperator {
        address nodeDelegator = nodeDelegatorQueue[ndcIndex];
        INodeDelegator(nodeDelegator).sendETHFromDepositPoolToNDC{ value: amount }();
    }

    /// @notice swap ETH for LST asset which is accepted by LRTDepositPool
    /// @dev use LRTOracle to get price for toToken. Only callable by LRT manager
    /// @param toAsset Asset address to swap to
    /// @param minToAssetAmount Minimum asset amount to swap to
    function swapETHForAssetWithinDepositPool(
        address toAsset,
        uint256 minToAssetAmount
    )
        external
        payable
        onlyLRTManager
        onlySupportedAsset(toAsset)
    {
        // checks
        uint256 ethAmountSent = msg.value;

        uint256 returnAmount = getSwapETHToAssetReturnAmount(toAsset, ethAmountSent);

        if (returnAmount < minToAssetAmount || IERC20(toAsset).balanceOf(address(this)) < returnAmount) {
            revert NotEnoughAssetToTransfer();
        }

        // interactions
        IERC20(toAsset).transfer(msg.sender, returnAmount);

        emit ETHSwappedForLST(ethAmountSent, toAsset, returnAmount);
    }

    /// @notice get return amount for swapping ETH to asset that is accepted by LRTDepositPool
    /// @dev use LRTOracle to get price for toToken
    /// @param toAsset Asset address to swap to
    /// @param ethAmountToSend Eth amount to swap from
    /// @return returnAmount Return amount of toAsset
    function getSwapETHToAssetReturnAmount(
        address toAsset,
        uint256 ethAmountToSend
    )
        public
        view
        returns (uint256 returnAmount)
    {
        address lrtOracleAddress = lrtConfig.getContract(LRTConstants.LRT_ORACLE);
        ILRTOracle lrtOracle = ILRTOracle(lrtOracleAddress);

        uint256 ethPricePerUint = 1e18;

        return ethPricePerUint * ethAmountToSend / lrtOracle.getAssetPrice(toAsset);
    }

    /// @notice swap assets that are accepted by LRTDepositPool
    /// @dev use LRTOracle to get price for fromToken to toToken. Only callable by LRT manager
    /// @param fromAsset Asset address to swap from
    /// @param toAsset Asset address to swap to
    /// @param fromAssetAmount Asset amount to swap from
    /// @param minToAssetAmount Minimum asset amount to swap to

    function swapAssetWithinDepositPool(
        address fromAsset,
        address toAsset,
        uint256 fromAssetAmount,
        uint256 minToAssetAmount
    )
        external
        onlyLRTManager
        onlySupportedAsset(fromAsset)
        onlySupportedAsset(toAsset)
    {
        // checks
        uint256 toAssetAmount = getSwapAssetReturnAmount(fromAsset, toAsset, fromAssetAmount);
        if (toAssetAmount < minToAssetAmount || IERC20(toAsset).balanceOf(address(this)) < toAssetAmount) {
            revert NotEnoughAssetToTransfer();
        }

        // interactions
        IERC20(fromAsset).transferFrom(msg.sender, address(this), fromAssetAmount);

        IERC20(toAsset).transfer(msg.sender, toAssetAmount);

        emit AssetSwapped(fromAsset, toAsset, fromAssetAmount, toAssetAmount);
    }

    /// @notice get return amount for swapping assets that are accepted by LRTDepositPool
    /// @dev use LRTOracle to get price for fromToken to toToken
    /// @param fromAsset Asset address to swap from
    /// @param toAsset Asset address to swap to
    /// @param fromAssetAmount Asset amount to swap from
    /// @return returnAmount Return amount of toAsset
    function getSwapAssetReturnAmount(
        address fromAsset,
        address toAsset,
        uint256 fromAssetAmount
    )
        public
        view
        returns (uint256 returnAmount)
    {
        address lrtOracleAddress = lrtConfig.getContract(LRTConstants.LRT_ORACLE);
        ILRTOracle lrtOracle = ILRTOracle(lrtOracleAddress);

        return lrtOracle.getAssetPrice(fromAsset) * fromAssetAmount / lrtOracle.getAssetPrice(toAsset);
    }

    /// @notice update max node delegator count
    /// @dev only callable by LRT admin
    /// @param maxNodeDelegatorLimit_ Maximum count of node delegator
    function updateMaxNodeDelegatorLimit(uint256 maxNodeDelegatorLimit_) external onlyLRTAdmin {
        if (maxNodeDelegatorLimit_ < nodeDelegatorQueue.length) {
            revert InvalidMaximumNodeDelegatorLimit();
        }

        maxNodeDelegatorLimit = maxNodeDelegatorLimit_;
        emit MaxNodeDelegatorLimitUpdated(maxNodeDelegatorLimit);
    }

    /// @notice update min amount to deposit
    /// @dev only callable by LRT admin
    /// @param minAmountToDeposit_ Minimum amount to deposit
    function setMinAmountToDeposit(uint256 minAmountToDeposit_) external onlyLRTAdmin {
        minAmountToDeposit = minAmountToDeposit_;
        emit MinAmountToDepositUpdated(minAmountToDeposit_);
    }

    /// @dev Triggers stopped state. Contract must not be paused.
    function pause() external onlyLRTManager {
        _pause();
    }

    /// @dev Returns to normal state. Contract must be paused
    function unpause() external onlyLRTAdmin {
        _unpause();
    }

    receive() external payable { }
}
