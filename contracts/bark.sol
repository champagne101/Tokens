// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

interface IDexRouter {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);
}

interface IDexFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

contract BARKALOT is Initializable, ERC20Upgradeable, OwnableUpgradeable {
    uint256 public maxBuyAmount;
    uint256 public maxSellAmount;
    uint256 public maxWalletAmount;

    IDexRouter public uniswapV2Router;
    address public uniswapV2Pair;

    bool private swapping;
    uint256 public swapTokensAtAmount;

    address public TreasuryAddress;
    address public BurnAddress;

    uint256 public tradingActiveBlock;
    uint256 public deadBlocks;

    bool public limitsInEffect;
    bool public tradingActive;
    bool public swapEnabled;

    uint256 public buyTax;
    uint256 public sellTax;
    uint256 public burnTax;
    uint256 public treasuryTax;

    uint256 public tokensForTreasury;
    uint256 public tokensForBurn;

    mapping(address => bool) private _isExcludedFromFees;
    mapping(address => bool) public _isExcludedMaxTransactionAmount;
    mapping(address => bool) public automatedMarketMakerPairs;

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
    event EnabledTrading(bool tradingActive, uint256 deadBlocks);
    event RemovedLimits();
    event ExcludeFromFees(address indexed account, bool isExcluded);
    event UpdatedMaxBuyAmount(uint256 newAmount);
    event UpdatedMaxSellAmount(uint256 newAmount);
    event UpdatedMaxWalletAmount(uint256 newAmount);
    event UpdatedTreasuryAddress(address indexed newWallet);
    event UpdatedBurnAddress(address indexed newBurnAddress);
    event MaxTransactionExclusion(address _address, bool excluded);
    event TransferForeignToken(address token, uint256 amount);
    event TokensBurned(uint256 amount);
    event UpdatedTaxes(uint256 burnTax, uint256 treasuryTax);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _TreasuryAddress,
        address _devWallet,
        address _router
    ) public initializer {
        __ERC20_init("BARK-A-LOT", "BARK");
        __Ownable_init();

        IDexRouter _uniswapV2Router = IDexRouter(_router);
        _excludeFromMaxTransaction(address(_uniswapV2Router), true);
        uniswapV2Router = _uniswapV2Router;

        uniswapV2Pair = IDexFactory(_uniswapV2Router.factory()).createPair(address(this), _uniswapV2Router.WETH());
        _setAutomatedMarketMakerPair(address(uniswapV2Pair), true);

        uint256 totalSupply = 1_000_000_000 * 10 ** decimals();

        maxBuyAmount = totalSupply * 10 / 1000;
        maxSellAmount = totalSupply * 10 / 1000;
        maxWalletAmount = totalSupply * 20 / 1000;
        swapTokensAtAmount = totalSupply * 50 / 100000;

        buyTax = 3;
        sellTax = 3;
        burnTax = 1;
        treasuryTax = 2;

        BurnAddress = 0x000000000000000000000000000000000000dEaD;

        limitsInEffect = true;
        tradingActive = false;
        swapEnabled = false;
        tradingActiveBlock = 0;
        deadBlocks = 1;

        _excludeFromMaxTransaction(owner(), true);
        _excludeFromMaxTransaction(address(this), true);
        _excludeFromMaxTransaction(BurnAddress, true);
        _excludeFromMaxTransaction(_devWallet, true);

        TreasuryAddress = _TreasuryAddress;

        excludeFromFees(owner(), true);
        excludeFromFees(address(this), true);
        excludeFromFees(BurnAddress, true);
        excludeFromFees(TreasuryAddress, true);
        excludeFromFees(_devWallet, true);

        _mint(owner(), totalSupply);
    }

    receive() external payable {}

    function updateMaxBuyAmount(uint256 newNum) external onlyOwner {
        require(newNum >= (totalSupply() * 1 / 1000) / 10 ** decimals(), "Cannot set max buy amount lower than 0.1%");
        maxBuyAmount = newNum * 10 ** decimals();
        emit UpdatedMaxBuyAmount(maxBuyAmount);
    }

    function updateMaxSellAmount(uint256 newNum) external onlyOwner {
        require(newNum >= (totalSupply() * 1 / 1000) / 10 ** decimals(), "Cannot set max sell amount lower than 0.1%");
        maxSellAmount = newNum * 10 ** decimals();
        emit UpdatedMaxSellAmount(maxSellAmount);
    }

    function removeLimits() external onlyOwner {
        limitsInEffect = false;
        emit RemovedLimits();
    }

    function _excludeFromMaxTransaction(address updAds, bool isExcluded) private {
        _isExcludedMaxTransactionAmount[updAds] = isExcluded;
        emit MaxTransactionExclusion(updAds, isExcluded);
    }

    function excludeFromMaxTransaction(address updAds, bool isEx) external onlyOwner {
        if (!isEx) {
            require(updAds != uniswapV2Pair, "Cannot remove uniswap pair from max txn");
        }
        _isExcludedMaxTransactionAmount[updAds] = isEx;
    }

    function updateMaxWalletAmount(uint256 newNum) external onlyOwner {
        require(newNum >= (totalSupply() * 3 / 1000) / 10 ** decimals(), "Cannot set max wallet amount lower than 0.3%");
        maxWalletAmount = newNum * 10 ** decimals();
        emit UpdatedMaxWalletAmount(maxWalletAmount);
    }

    function updateSwapThreshold(uint256 newAmount) public {
        require(msg.sender == TreasuryAddress, "only TreasuryAddress can change swapThreshold");
        swapTokensAtAmount = newAmount * 10 ** decimals();
    }

    function transferForeignToken(address _token, address _to) public returns (bool _sent) {
        require(_token != address(0), "_token address cannot be 0");
        require(msg.sender == TreasuryAddress, "only TreasuryAddress can withdraw");
        uint256 _contractBalance = IERC20Upgradeable(_token).balanceOf(address(this));
        _sent = IERC20Upgradeable(_token).transfer(_to, _contractBalance);
        emit TransferForeignToken(_token, _contractBalance);
    }

    function withdrawStuckETH() public {
        require(msg.sender == TreasuryAddress, "only TreasuryAddress can withdraw");
        (bool success,) = address(msg.sender).call{value: address(this).balance}("");
        require(success, "ETH transfer failed");
    }

    function updateTaxes(uint256 _burnTax, uint256 _treasuryTax) external onlyOwner {
        require(_burnTax + _treasuryTax <= 10, "Total tax cannot exceed 10%");
        burnTax = _burnTax;
        treasuryTax = _treasuryTax;
        emit UpdatedTaxes(burnTax, treasuryTax);
    }

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        _isExcludedFromFees[account] = excluded;
        emit ExcludeFromFees(account, excluded);
    }

    function updateTreasuryAddress(address _TreasuryAddress) external onlyOwner {
        require(_TreasuryAddress != address(0), "_TreasuryAddress address cannot be 0");
        TreasuryAddress = _TreasuryAddress;
        emit UpdatedTreasuryAddress(_TreasuryAddress);
    }

    function updateBurnAddress(address _BurnAddress) external onlyOwner {
        require(_BurnAddress != address(0), "_BurnAddress address cannot be 0");
        BurnAddress = _BurnAddress;
        emit UpdatedBurnAddress(_BurnAddress);
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "amount must be greater than 0");

        if (limitsInEffect) {
            if (from != owner() && to != owner() && to != address(0) && to != address(0xdead)) {
                if (!tradingActive) {
                    require(_isExcludedMaxTransactionAmount[from] || _isExcludedMaxTransactionAmount[to], "Trading is not active.");
                    require(from == owner(), "Trading is not enabled");
                }
                if (automatedMarketMakerPairs[from] && !_isExcludedMaxTransactionAmount[to]) {
                    require(amount <= maxBuyAmount, "Buy transfer amount exceeds the max buy.");
                    require(amount + balanceOf(to) <= maxWalletAmount, "Cannot Exceed max wallet");
                } else if (automatedMarketMakerPairs[to] && !_isExcludedMaxTransactionAmount[from]) {
                    require(amount <= maxSellAmount, "Sell transfer amount exceeds the max sell.");
                } else if (!_isExcludedMaxTransactionAmount[to] && !_isExcludedMaxTransactionAmount[from]) {
                    require(amount + balanceOf(to) <= maxWalletAmount, "Cannot Exceed max wallet");
                }
            }
        }

        uint256 contractTokenBalance = balanceOf(address(this));
        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

        if (canSwap && swapEnabled && !swapping && !automatedMarketMakerPairs[from] && !_isExcludedFromFees[from] && !_isExcludedFromFees[to]) {
            swapping = true;
            swapBack();
            swapping = false;
        }

        bool takeFee = true;
        if (_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }

        uint256 fees = 0;
        uint256 treasuryAmount = 0;
        uint256 burnAmount = 0;

        if (takeFee && tradingActiveBlock > 0 && (block.number > tradingActiveBlock)) {
            if (automatedMarketMakerPairs[to] && sellTax > 0) {
                fees = amount * sellTax / 100;
                treasuryAmount = fees * treasuryTax / sellTax;
                burnAmount = fees * burnTax / sellTax;
                tokensForTreasury += treasuryAmount;
                tokensForBurn += burnAmount;
            } else if (automatedMarketMakerPairs[from] && buyTax > 0) {
                fees = amount * buyTax / 100;
                treasuryAmount = fees * treasuryTax / buyTax;
                burnAmount = fees * burnTax / buyTax;
                tokensForTreasury += treasuryAmount;
                tokensForBurn += burnAmount;
            }

            if (fees > 0) {
                super._transfer(from, address(this), fees);
            }

            if (burnAmount > 0) {
                _burnTokens(burnAmount);
            }

            amount -= fees;
        }

        super._transfer(from, to, amount);
    }

    function _burnTokens(uint256 amount) private {
        if (amount > 0) {
            super._transfer(address(this), BurnAddress, amount);
            emit TokensBurned(amount);
        }
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function setAutomatedMarketMakerPair(address pair, bool value) external onlyOwner {
        require(pair != uniswapV2Pair, "The pair cannot be removed from automatedMarketMakerPairs");
        _setAutomatedMarketMakerPair(pair, value);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        automatedMarketMakerPairs[pair] = value;
        _excludeFromMaxTransaction(pair, value);
        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) external payable onlyOwner {
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0,
            0,
            owner(),
            block.timestamp
        );
    }

    function swapBack() private {
        uint256 contractBalance = balanceOf(address(this));
        if (contractBalance == 0 || tokensForTreasury == 0) {
            return;
        }

        if (contractBalance > swapTokensAtAmount * 5) {
            contractBalance = swapTokensAtAmount * 5;
        }

        swapTokensForEth(contractBalance);
        
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            (bool success,) = address(TreasuryAddress).call{value: ethBalance}("");
            require(success, "ETH transfer failed");
        }
        
        tokensForTreasury = 0;
        tokensForBurn = 0;
    }

    function manualSwap() external {
        require(_msgSender() == TreasuryAddress, "Only treasury can manual swap");
        uint256 tokenBalance = balanceOf(address(this));
        if (tokenBalance > 0) {
            swapping = true;
            swapBack();
            swapping = false;
        }
    }

    function enableTrading(bool _status, uint256 _deadBlocks) external onlyOwner {
        require(!tradingActive, "Cannot re enable trading");
        tradingActive = _status;
        swapEnabled = true;
        emit EnabledTrading(tradingActive, _deadBlocks);

        if (tradingActive && tradingActiveBlock == 0) {
            tradingActiveBlock = block.number;
            deadBlocks = _deadBlocks;
        }
    }
}
