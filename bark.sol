// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/* 
 * Bark-A-Lot (BARK)
 * Upgradeable ERC20 
 */

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

interface IDexFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IDexRouter {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
}

contract BARK is 
    ERC20Upgradeable, 
    OwnableUpgradeable, 
    UUPSUpgradeable 
{
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 1e18;

    uint256 public buyTax;   // 3%
    uint256 public sellTax;  // 3%

    address public treasury;

    IDexRouter public router;
    address public pair;

    mapping(address => bool) public automatedMarketMakerPairs;
    mapping(address => bool) private _isExcludedFromFees;

    event SetAMMPair(address pair, bool value);
    event ExcludeFromFees(address account, bool excluded);
    event TreasuryUpdated(address newTreasury);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _router,
        address _treasury
    ) public initializer {
        __ERC20_init("Bark-A-Lot", "BARK");
        __Ownable_init();
        __UUPSUpgradeable_init();

        require(_treasury != address(0), "Invalid treasury");

        treasury = _treasury;
        buyTax = 3;
        sellTax = 3;

        router = IDexRouter(_router);

        pair = IDexFactory(router.factory()).createPair(
            address(this),
            router.WETH()
        );

        automatedMarketMakerPairs[pair] = true;

        // mint full supply to owner
        _mint(msg.sender, MAX_SUPPLY);

        // exclusions
        _isExcludedFromFees[msg.sender] = true;
        _isExcludedFromFees[address(this)] = true;
        _isExcludedFromFees[treasury] = true;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // =========================
    // CONFIG
    // =========================

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Zero address");
        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }

    function setTaxes(uint256 _buy, uint256 _sell) external onlyOwner {
        require(_buy <= 10 && _sell <= 10, "Too high"); // safety cap
        buyTax = _buy;
        sellTax = _sell;
    }

    function excludeFromFees(address account, bool excluded) external onlyOwner {
        _isExcludedFromFees[account] = excluded;
        emit ExcludeFromFees(account, excluded);
    }

    function setAMMPair(address _pair, bool value) external onlyOwner {
        automatedMarketMakerPairs[_pair] = value;
        emit SetAMMPair(_pair, value);
    }

    // =========================
    // TAX LOGIC
    // =========================

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {

        if (_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            super._transfer(from, to, amount);
            return;
        }

        uint256 fee = 0;

        if (automatedMarketMakerPairs[from] && buyTax > 0) {
            fee = (amount * buyTax) / 100;
        }
        else if (automatedMarketMakerPairs[to] && sellTax > 0) {
            fee = (amount * sellTax) / 100;
        }

        if (fee > 0) {
            super._transfer(from, treasury, fee);
            amount -= fee;
        }

        super._transfer(from, to, amount);
    }
}
