// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;


/**
 * @dev Minimal ERC-1967 storage slot helpers used by the proxy.
 *      
 */

// ─── Initializable ───────────────────────────────────────────

abstract contract Initializable {
    uint8 private _initialized;
    bool  private _initializing;

    event Initialized(uint8 version);

    modifier initializer() {
        bool isTopLevelCall = !_initializing;
        require(
            (isTopLevelCall && _initialized < 1) ||
            (!isTopLevelCall && _initialized == 1),
            "Initializable: contract is already initialized"
        );
        _initialized   = 1;
        _initializing  = isTopLevelCall;
        _;
        if (isTopLevelCall) {
            _initializing = false;
            emit Initialized(1);
        }
    }

    modifier reinitializer(uint8 version) {
        require(
            !_initializing && _initialized < version,
            "Initializable: contract is already initialized"
        );
        _initialized  = version;
        _initializing = true;
        _;
        _initializing = false;
        emit Initialized(version);
    }

    function _disableInitializers() internal virtual {
        require(!_initializing, "Initializable: contract is initializing");
        if (_initialized < type(uint8).max) {
            _initialized = type(uint8).max;
            emit Initialized(type(uint8).max);
        }
    }
}

// ─── UUPSUpgradeable (ERC-1967 implementation slot) ──────────

abstract contract UUPSUpgradeable {
    // ERC-1967 implementation slot:
    // keccak256("eip1967.proxy.implementation") - 1
    bytes32 private constant _IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    event Upgraded(address indexed implementation);

    function upgradeTo(address newImplementation) external virtual {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCall(newImplementation, bytes(""), false);
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) external payable virtual {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCall(newImplementation, data, true);
    }

    function _upgradeToAndCall(address newImplementation, bytes memory data, bool forceCall) internal {
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);
        if (data.length > 0 || forceCall) {
            (bool success,) = newImplementation.delegatecall(data);
            require(success, "UUPS: upgrade call failed");
        }
    }

    function _setImplementation(address newImplementation) private {
        require(
            newImplementation.code.length > 0,
            "UUPS: new implementation is not a contract"
        );
        assembly {
            sstore(_IMPLEMENTATION_SLOT, newImplementation)
        }
    }

    function _getImplementation() internal view returns (address impl) {
        assembly { impl := sload(_IMPLEMENTATION_SLOT) }
    }

    /// @dev Override this with an access-control check (e.g. onlyOwner).
    function _authorizeUpgrade(address newImplementation) internal virtual;
}

// ─── Context ─────────────────────────────────────────────────

abstract contract Context {
    function _msgSender() internal view virtual returns (address) { return msg.sender; }
    function _msgData()   internal view virtual returns (bytes calldata) { this; return msg.data; }
}

// ─── IERC20 / IERC20Metadata ─────────────────────────────────

interface IERC20 {
    function totalSupply()                                         external view returns (uint256);
    function balanceOf(address account)                            external view returns (uint256);
    function transfer(address recipient, uint256 amount)           external returns (bool);
    function allowance(address owner, address spender)             external view returns (uint256);
    function approve(address spender, uint256 amount)              external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IERC20Metadata is IERC20 {
    function name()     external view returns (string memory);
    function symbol()   external view returns (string memory);
    function decimals() external view returns (uint8);
}

// ─── ERC20 (storage-compatible with proxy pattern) ───────────

contract ERC20 is Context, IERC20, IERC20Metadata {
    mapping(address => uint256)                     private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    string  private _name;
    string  private _symbol;

    // NOTE: No constructor — initialised via _erc20Init in the upgradeable contract.

    function _erc20Init(string memory name_, string memory symbol_) internal {
        _name   = name_;
        _symbol = symbol_;
    }

    function name()        public view virtual override returns (string memory) { return _name; }
    function symbol()      public view virtual override returns (string memory) { return _symbol; }
    function decimals()    public view virtual override returns (uint8)          { return 18; }
    function totalSupply() public view virtual override returns (uint256)        { return _totalSupply; }
    function balanceOf(address account) public view virtual override returns (uint256) { return _balances[account]; }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        unchecked { _approve(sender, _msgSender(), currentAllowance - amount); }
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked { _approve(_msgSender(), spender, currentAllowance - subtractedValue); }
        return true;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        require(sender    != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked { _balances[sender] = senderBalance - amount; }
        _balances[recipient] += amount;
        emit Transfer(sender, recipient, amount);
    }

    function _createInitialSupply(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");
        _totalSupply         += amount;
        _balances[account]   += amount;
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");
        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked { _balances[account] = accountBalance - amount; }
        _totalSupply -= amount;
        emit Transfer(account, address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner   != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
}

// ─── Ownable (initializable) ─────────────────────────────────

contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function _ownerInit(address initialOwner) internal {
        _owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    function owner() public view returns (address) { return _owner; }

    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() external virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

// ─── DEX interfaces ──────────────────────────────────────────

interface IDexRouter {
    function factory() external pure returns (address);
    function WETH()    external pure returns (address);
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline
    ) external;
    function addLiquidityETH(
        address token, uint256 amountTokenDesired,
        uint256 amountTokenMin, uint256 amountETHMin,
        address to, uint256 deadline
    ) external payable returns (uint256, uint256, uint256);
}

interface IDexFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

// ─── BARK-A-LOT ──────────────────────────────────────────────

/**
 * @title  BARK-A-LOT
 * @notice ERC-20 token deployable behind a TransparentUpgradeableProxy.
 *         Tax: 3 % on buys and sells — 1 % burnt, 2 % to treasury.
 */
contract BARKALOT is Initializable, UUPSUpgradeable, ERC20, Ownable {

    // ── Limits ────────────────────────────────────────────────
    uint256 public maxBuyAmount;
    uint256 public maxSellAmount;
    uint256 public maxWalletAmount;

    // ── DEX ───────────────────────────────────────────────────
    IDexRouter public uniswapV2Router;
    address    public uniswapV2Pair;

    // ── Swap ──────────────────────────────────────────────────
    bool     private swapping;
    uint256  public  swapTokensAtAmount;

    // ── Addresses ─────────────────────────────────────────────
    address public TreasuryAddress;

    // ── Trading flags ─────────────────────────────────────────
    uint256 public tradingActiveBlock;  // 0
    uint256 public deadBlocks;
    bool    public limitsInEffect;
    bool    public tradingActive;
    bool    public swapEnabled;


    uint256 public buyFee;   
    uint256 public sellFee;  
    uint256 public burnBps; 

    uint256 public tokensForTreasury;
    uint256 public tokensForBurn;

    // ── Mappings ──────────────────────────────────────────────
    mapping(address => bool) private _isExcludedFromFees;
    mapping(address => bool) public  _isExcludedMaxTransactionAmount;
    mapping(address => bool) public  automatedMarketMakerPairs;

    // ── Events ────────────────────────────────────────────────
    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
    event EnabledTrading(bool tradingActive, uint256 deadBlocks);
    event RemovedLimits();
    event ExcludeFromFees(address indexed account, bool isExcluded);
    event UpdatedMaxBuyAmount(uint256 newAmount);
    event UpdatedMaxSellAmount(uint256 newAmount);
    event UpdatedMaxWalletAmount(uint256 newAmount);
    event UpdatedTreasuryAddress(address indexed newWallet);
    event MaxTransactionExclusion(address _address, bool excluded);
    event TokensBurnt(uint256 amount);
    event TransferForeignToken(address token, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ══════════════════════════════════════════════════════════
    //  INITIALIZER  (replaces constructor for proxy pattern)
    // ══════════════════════════════════════════════════════════

    /**
     * @param _TreasuryAddress  Wallet that receives the 2 % treasury cut.
     * @param _devWallet        Dev wallet — excluded from fees/limits.
     * @param _initialOwner     Address that becomes the owner.
     */
    function initialize(
        address _TreasuryAddress,
        address _devWallet,
        address _initialOwner
    ) external initializer {

        // ERC-20 metadata
        _erc20Init("BARK-A-LOT", "BARK");

        // Ownership
        _ownerInit(_initialOwner);

        // ── DEX setup ──────────────────────────────────────────
        IDexRouter _router = IDexRouter(0xF284893Cff5ADd6745ed00c779D784d53915b441);
        _excludeFromMaxTransaction(address(_router), true);
        uniswapV2Router = _router;
        uniswapV2Pair   = IDexFactory(_router.factory()).createPair(address(this), _router.WETH());
        _setAutomatedMarketMakerPair(address(uniswapV2Pair), true);

        // ── Supply ─────────────────────────────────────────────
        uint256 totalSupply = 1_000_000_000 * 1e18;

        // ── Limits ─────────────────────────────────────────────
        maxBuyAmount        = totalSupply *  10 / 1000;   
        maxSellAmount       = totalSupply *  10 / 1000;   
        maxWalletAmount     = totalSupply *  20 / 1000;   
        swapTokensAtAmount  = totalSupply *  50 / 100000; 

        // ── Fees ───────────────────────────────────────────────
        buyFee  = 3;  
        sellFee = 3;   
        burnBps = 3333;

        // ── Flags ──────────────────────────────────────────────
        limitsInEffect     = true;
        tradingActive      = false;
        swapEnabled        = false;
        tradingActiveBlock = 0;
        deadBlocks         = 1;

        // ── Exclusions ─────────────────────────────────────────
        _excludeFromMaxTransaction(_initialOwner, true);
        _excludeFromMaxTransaction(address(this),   true);
        _excludeFromMaxTransaction(address(0xdead), true);
        _excludeFromMaxTransaction(_devWallet,      true);

        TreasuryAddress = _TreasuryAddress;

        excludeFromFees(_initialOwner,    true);
        excludeFromFees(address(this),    true);
        excludeFromFees(address(0xdead),  true);
        excludeFromFees(TreasuryAddress,  true);
        excludeFromFees(_devWallet,       true);

        // ── Mint ───────────────────────────────────────────────
        _createInitialSupply(_initialOwner, totalSupply);
    }

    receive() external payable {}

    // ── UUPS: only owner may upgrade ──────────────────────────
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ══════════════════════════════════════════════════════════
    //  ADMIN — LIMITS & FEES
    // ══════════════════════════════════════════════════════════

    function updateMaxBuyAmount(uint256 newNum) external onlyOwner {
        require(newNum >= (totalSupply() * 1 / 1000) / 1e18, "Cannot set max buy amount lower than 0.1%");
        maxBuyAmount = newNum * 1e18;
        emit UpdatedMaxBuyAmount(maxBuyAmount);
    }

    function updateMaxSellAmount(uint256 newNum) external onlyOwner {
        require(newNum >= (totalSupply() * 1 / 1000) / 1e18, "Cannot set max sell amount lower than 0.1%");
        maxSellAmount = newNum * 1e18;
        emit UpdatedMaxSellAmount(maxSellAmount);
    }

    function updateMaxWalletAmount(uint256 newNum) external onlyOwner {
        require(newNum >= (totalSupply() * 3 / 1000) / 1e18, "Cannot set max wallet amount lower than 0.3%");
        maxWalletAmount = newNum * 1e18;
        emit UpdatedMaxWalletAmount(maxWalletAmount);
    }

    function removeLimits() external onlyOwner {
        limitsInEffect = false;
        emit RemovedLimits();
    }

    /**
     * @notice Update buy/sell fees. Both capped at 10 %.
     *         Burn split stays at 1/3 of the fee (≈33.33 %).
     */
    function updateBuyFee(uint256 _fee) external onlyOwner {
        require(_fee <= 10, "Fees must be 10% or less");
        buyFee = _fee;
    }

    function updateSellFee(uint256 _fee) external onlyOwner {
        require(_fee <= 10, "Fees must be 10% or less");
        sellFee = _fee;
    }

    /**
     * @notice Adjust the fraction of the collected fee that is burnt.
     */
    function updateBurnBps(uint256 _bps) external onlyOwner {
        require(_bps <= 10000, "Cannot exceed 100%");
        burnBps = _bps;
    }

    // ══════════════════════════════════════════════════════════
    //  ADMIN — TREASURY & SWAP
    // ══════════════════════════════════════════════════════════

    function setTreasuryAddress(address _TreasuryAddress) external onlyOwner {
        require(_TreasuryAddress != address(0), "_TreasuryAddress cannot be 0");
        TreasuryAddress = payable(_TreasuryAddress);
        emit UpdatedTreasuryAddress(_TreasuryAddress);
    }

    function updateSwapThreshold(uint256 newAmount) public {
        require(msg.sender == TreasuryAddress, "only TreasuryAddress");
        swapTokensAtAmount = newAmount * 1e18;
    }

    function transferForeignToken(address _token, address _to) public returns (bool _sent) {
        require(_token != address(0), "_token address cannot be 0");
        require(msg.sender == TreasuryAddress, "only TreasuryAddress");
        uint256 bal = IERC20(_token).balanceOf(address(this));
        _sent = IERC20(_token).transfer(_to, bal);
        emit TransferForeignToken(_token, bal);
    }

    function withdrawStuckETH() public {
        require(msg.sender == TreasuryAddress, "only TreasuryAddress");
        (bool success,) = address(msg.sender).call{value: address(this).balance}("");
        require(success, "ETH transfer failed");
    }

    function manualSwap() external {
        require(_msgSender() == TreasuryAddress, "only TreasuryAddress");
        uint256 bal = balanceOf(address(this));
        if (bal > 0) {
            swapping = true;
            swapBack();
            swapping = false;
        }
    }

    // ══════════════════════════════════════════════════════════
    //  ADMIN — EXCLUSIONS & PAIRS
    // ══════════════════════════════════════════════════════════

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        _isExcludedFromFees[account] = excluded;
        emit ExcludeFromFees(account, excluded);
    }

    function excludeFromMaxTransaction(address updAds, bool isEx) external onlyOwner {
        if (!isEx) require(updAds != uniswapV2Pair, "Cannot remove uniswap pair from max txn");
        _isExcludedMaxTransactionAmount[updAds] = isEx;
    }

    function setAutomatedMarketMakerPair(address pair, bool value) external onlyOwner {
        require(pair != uniswapV2Pair, "The pair cannot be removed from automatedMarketMakerPairs");
        _setAutomatedMarketMakerPair(pair, value);
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) external onlyOwner {
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this), tokenAmount, 0, 0, owner(), block.timestamp
        );
    }

    function enableTrading(bool _status, uint256 _deadBlocks) external onlyOwner {
        require(!tradingActive, "Cannot re-enable trading");
        tradingActive = _status;
        swapEnabled   = true;
        emit EnabledTrading(tradingActive, _deadBlocks);
        if (tradingActive && tradingActiveBlock == 0) {
            tradingActiveBlock = block.number;
            deadBlocks         = _deadBlocks;
        }
    }

    // ══════════════════════════════════════════════════════════
    //  TRANSFER LOGIC
    // ══════════════════════════════════════════════════════════

    function _transfer(address from, address to, uint256 amount) internal override {
        require(from   != address(0), "ERC20: transfer from the zero address");
        require(to     != address(0), "ERC20: transfer to the zero address");
        require(amount  > 0,          "amount must be greater than 0");

        // ── Limits ─────────────────────────────────────────────
        if (limitsInEffect) {
            if (from != owner() && to != owner() && to != address(0) && to != address(0xdead)) {
                if (!tradingActive) {
                    require(
                        _isExcludedMaxTransactionAmount[from] || _isExcludedMaxTransactionAmount[to],
                        "Trading is not active."
                    );
                    require(from == owner(), "Trading is not enabled");
                }
                // buy
                if (automatedMarketMakerPairs[from] && !_isExcludedMaxTransactionAmount[to]) {
                    require(amount <= maxBuyAmount, "Buy transfer amount exceeds the max buy.");
                    require(amount + balanceOf(to) <= maxWalletAmount, "Cannot exceed max wallet");
                }
                // sell
                else if (automatedMarketMakerPairs[to] && !_isExcludedMaxTransactionAmount[from]) {
                    require(amount <= maxSellAmount, "Sell transfer amount exceeds the max sell.");
                }
                // wallet-to-wallet
                else if (!_isExcludedMaxTransactionAmount[to] && !_isExcludedMaxTransactionAmount[from]) {
                    require(amount + balanceOf(to) <= maxWalletAmount, "Cannot exceed max wallet");
                }
            }
        }

        uint256 contractTokenBalance = balanceOf(address(this));
        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

        if (canSwap && swapEnabled && !swapping &&
            !automatedMarketMakerPairs[from] &&
            !_isExcludedFromFees[from] && !_isExcludedFromFees[to]) {
            swapping = true;
            swapBack();
            swapping = false;
        }

        bool takeFee = !(_isExcludedFromFees[from] || _isExcludedFromFees[to]);

        if (takeFee && tradingActiveBlock > 0 && block.number > tradingActiveBlock) {
            uint256 feeRate = 0;

            if (automatedMarketMakerPairs[to]   && sellFee > 0) feeRate = sellFee;
            else if (automatedMarketMakerPairs[from] && buyFee > 0)  feeRate = buyFee;

            if (feeRate > 0) {
                uint256 totalFee = amount * feeRate / 100;

                uint256 burnAmount     = totalFee * burnBps / 10000;
                uint256 treasuryAmount = totalFee - burnAmount;

                tokensForTreasury += treasuryAmount;
                tokensForBurn     += burnAmount;

                super._transfer(from, address(this), totalFee);
                amount -= totalFee;
            }
        }

        super._transfer(from, to, amount);
    }

    // ══════════════════════════════════════════════════════════
    //  SWAP & BURN
    // ══════════════════════════════════════════════════════════

    function swapTokensForEth(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount, 0, path, address(this), block.timestamp
        );
    }

    function swapBack() private {
        uint256 contractBalance = balanceOf(address(this));
        if (contractBalance == 0) return;

        uint256 burnNow = tokensForBurn;
        if (burnNow > 0 && burnNow <= contractBalance) {
            _burn(address(this), burnNow);
            emit TokensBurnt(burnNow);
            tokensForBurn   = 0;
            contractBalance = balanceOf(address(this));
        }

        uint256 treasuryTokens = tokensForTreasury;
        if (treasuryTokens == 0 || contractBalance == 0) return;

        uint256 toSwap = contractBalance > swapTokensAtAmount * 5
            ? swapTokensAtAmount * 5
            : contractBalance;

        swapTokensForEth(toSwap);
        tokensForTreasury = 0;

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            (bool success,) = address(TreasuryAddress).call{value: ethBalance}("");
            require(success, "ETH transfer to treasury failed");
        }
    }

    // ══════════════════════════════════════════════════════════
    //  INTERNAL HELPERS
    // ══════════════════════════════════════════════════════════

    function _excludeFromMaxTransaction(address updAds, bool isExcluded) private {
        _isExcludedMaxTransactionAmount[updAds] = isExcluded;
        emit MaxTransactionExclusion(updAds, isExcluded);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        automatedMarketMakerPairs[pair] = value;
        _excludeFromMaxTransaction(pair, value);
        emit SetAutomatedMarketMakerPair(pair, value);
    }
}

