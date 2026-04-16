// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IERC20Metadata is IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}


contract BarkStorage {
    mapping(address => uint256) internal _balances;
    mapping(address => mapping(address => uint256)) internal _allowances;
    uint256 internal _totalSupply;
    string  internal _name;
    string  internal _symbol;

    address internal _owner;

    struct RouterPair {
        IDexRouter router;
        address    pair;
        address    baseToken;
        bool       isActive;
    }
    mapping(address => RouterPair) public routerPairs;
    address[]                      public activeRouters;

    IDexRouter public defaultRouter;
    address    public defaultBaseToken;

    uint256 public constant TOTAL_FEE    = 3;
    uint256 public constant BURN_FEE     = 1;  
    uint256 public constant TREASURY_FEE = 2;   

    bool    internal _swapping;
    uint256 public  swapTokensAtAmount;

    address public TreasuryAddress;

    uint256 public tradingActiveBlock;
    uint256 public deadBlocks;
    bool    public tradingActive;
    bool    public swapEnabled;

    uint256 public tokensForTreasury;
    uint256 public totalBurned;         

    mapping(address => bool) internal _isExcludedFromFees;
    mapping(address => bool) public  automatedMarketMakerPairs;
    mapping(address => bool) public  isRouter;

    bool internal _initialized;
}


interface IDexRouter {
    function factory() external pure returns (address);
    function WETH()    external pure returns (address);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint    amountIn,
        uint    amountOutMin,
        address[] calldata path,
        address to,
        uint    deadline
    ) external;

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint    amountIn,
        uint    amountOutMin,
        address[] calldata path,
        address to,
        uint    deadline
    ) external;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint    amountOutMin,
        address[] calldata path,
        address to,
        uint    deadline
    ) external payable;

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256, uint256, uint256);
}

interface IDexFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}



contract ProxyAdmin {
    address public owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Upgraded(address indexed proxy, address indexed newImplementation);

    modifier onlyOwner() {
        require(msg.sender == owner, "ProxyAdmin: caller is not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "ProxyAdmin: zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    /// @notice Upgrade `proxy` to point at `newImplementation`.
    function upgrade(address proxy, address newImplementation) external onlyOwner {
        BarkProxy(payable(proxy)).upgradeTo(newImplementation);
        emit Upgraded(proxy, newImplementation);
    }

    /// @notice Upgrade and immediately call an initialiser on the new implementation.
    function upgradeAndCall(
        address proxy,
        address newImplementation,
        bytes calldata data
    ) external payable onlyOwner {
        BarkProxy(payable(proxy)).upgradeToAndCall{value: msg.value}(newImplementation, data);
        emit Upgraded(proxy, newImplementation);
    }

    function getImplementation(address proxy) external returns (address) {
        return BarkProxy(payable(proxy)).implementation();
    }
}



contract BarkProxy is BarkStorage {

    bytes32 private constant _IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 private constant _ADMIN_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    event Upgraded(address indexed implementation);
    event AdminChanged(address previousAdmin, address newAdmin);

    constructor(address _implementation, address _admin, bytes memory _data) {
        _setImplementation(_implementation);
        _setAdmin(_admin);
        if (_data.length > 0) {
            (bool ok,) = _implementation.delegatecall(_data);
            require(ok, "BarkProxy: initialisation failed");
        }
    }

    receive() external payable {}


    modifier ifAdmin() {
        if (msg.sender == _getAdmin()) {
            _;
        } else {
            _fallback();
        }
    }

    function implementation() external ifAdmin returns (address) {
        return _getImplementation();
    }

    function admin() external ifAdmin returns (address) {
        return _getAdmin();
    }

    function changeAdmin(address newAdmin) external ifAdmin {
        require(newAdmin != address(0), "BarkProxy: zero admin");
        emit AdminChanged(_getAdmin(), newAdmin);
        _setAdmin(newAdmin);
    }

    function upgradeTo(address newImplementation) external ifAdmin {
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);
    }

    function upgradeToAndCall(address newImplementation, bytes calldata data)
        external payable ifAdmin
    {
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);
        (bool ok,) = newImplementation.delegatecall(data);
        require(ok, "BarkProxy: upgradeToAndCall failed");
    }


    fallback() external payable {
        _fallback();
    }

    function _fallback() internal {
        address impl = _getImplementation();
        require(impl != address(0), "BarkProxy: no implementation");
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    // ── EIP-1967 helpers ──────────────────────────────────────

    function _getImplementation() internal view returns (address impl) {
        assembly { impl := sload(_IMPLEMENTATION_SLOT) }
    }

    function _setImplementation(address impl) internal {
        require(impl.code.length > 0, "BarkProxy: not a contract");
        assembly { sstore(_IMPLEMENTATION_SLOT, impl) }
    }

    function _getAdmin() internal view returns (address adm) {
        assembly { adm := sload(_ADMIN_SLOT) }
    }

    function _setAdmin(address adm) internal {
        assembly { sstore(_ADMIN_SLOT, adm) }
    }
}



contract BarkImplementationV1 is BarkStorage {

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
    event EnabledTrading(bool tradingActive, uint256 deadBlocks);
    event ExcludeFromFees(address indexed account, bool isExcluded);
    event UpdatedTreasuryAddress(address indexed newWallet);
    event TransferForeignToken(address token, uint256 amount);
    event UpdatedSwapThreshold(uint256 newAmount);
    event WithdrewStuckETH(uint256 amount);
    event RouterAdded(address indexed router, address indexed baseToken, address pair);
    event RouterRemoved(address indexed router);
    event RouterActivated(address indexed router, bool isActive);
    event TokensBurned(address indexed from, uint256 amount);
    event FeesProcessed(uint256 treasuryEthAmount);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);


    modifier onlyOwner() {
        require(_owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }


    function initialize(
        address _treasuryAddress,
        address _devWallet,
        address _routerAddress,
        address _baseToken
    ) external {
        require(!_initialized, "Already initialized");
        _initialized = true;

        _name   = "Bark A Lot";
        _symbol = "BARK";

        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);

        defaultRouter    = IDexRouter(_routerAddress);
        defaultBaseToken = _baseToken;

        isRouter[_routerAddress] = true;
        _setExcluded(_routerAddress, true);

        address defaultPair = IDexFactory(defaultRouter.factory())
            .createPair(address(this), _baseToken);
        _setAMMPair(defaultPair, true);

        routerPairs[_routerAddress] = RouterPair({
            router:    defaultRouter,
            pair:      defaultPair,
            baseToken: _baseToken,
            isActive:  true
        });
        activeRouters.push(_routerAddress);

        // Supply - FIXED: Use different variable name to avoid shadowing
        uint256 initialSupply = 1_000_000_000 * 1e18;
        swapTokensAtAmount  = (initialSupply * 50) / 100_000; 

        // Fee exclusions
        _setExcluded(msg.sender,        true);
        _setExcluded(address(this),     true);
        _setExcluded(address(0xdead),   true);
        _setExcluded(_devWallet,        true);
        _setExcluded(_treasuryAddress,  true);

        TreasuryAddress = _treasuryAddress;

        // Mint - Use the renamed variable
        _totalSupply            += initialSupply;
        _balances[msg.sender]   += initialSupply;
        emit Transfer(address(0), msg.sender, initialSupply);

        tradingActive      = false;
        swapEnabled        = false;
        tradingActiveBlock = 0;
        deadBlocks         = 1;
    }

   

    function name()        public view returns (string memory) { return _name; }
    function symbol()      public view returns (string memory) { return _symbol; }
    function decimals()    public pure returns (uint8)         { return 18; }
    function totalSupply() public view returns (uint256)       { return _totalSupply; }
    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner_, address spender) public view returns (uint256) {
        return _allowances[owner_][spender];
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transfer(address recipient, uint256 amount) public returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount)
        public returns (bool)
    {
        _transfer(sender, recipient, amount);
        uint256 currentAllowance = _allowances[sender][msg.sender];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        unchecked { _approve(sender, msg.sender, currentAllowance - amount); }
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public returns (bool) {
        uint256 current = _allowances[msg.sender][spender];
        require(current >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked { _approve(msg.sender, spender, current - subtractedValue); }
        return true;
    }

   

    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to   != address(0), "ERC20: transfer to the zero address");
        require(amount > 0,         "amount must be greater than 0");

        bool isActivePair = false;
        for (uint i = 0; i < activeRouters.length; i++) {
            RouterPair memory rp = routerPairs[activeRouters[i]];
            if (rp.isActive && (from == rp.pair || to == rp.pair)) {
                isActivePair = true;
                break;
            }
        }

        uint256 contractTokenBalance = _balances[address(this)];
        if (
            contractTokenBalance >= swapTokensAtAmount &&
            swapEnabled &&
            !_swapping &&
            !isActivePair &&
            !_isExcludedFromFees[from] &&
            !_isExcludedFromFees[to]
        ) {
            _swapping = true;
            _swapBack();
            _swapping = false;
        }

        bool takeFee = true;
        if (
            _isExcludedFromFees[from] ||
            _isExcludedFromFees[to]   ||
            isRouter[from]            ||
            isRouter[to]
        ) {
            takeFee = false;
        }

        if (
            takeFee &&
            tradingActive &&
            tradingActiveBlock > 0 &&
            block.number > tradingActiveBlock + deadBlocks &&
            isActivePair
        ) {
            uint256 burnAmount     = amount * BURN_FEE     / 100;
            uint256 treasuryAmount = amount * TREASURY_FEE / 100;
            uint256 totalFees      = burnAmount + treasuryAmount;

            if (totalFees > 0) {
                if (burnAmount > 0) {
                    _rawTransfer(from, address(0xdead), burnAmount);
                    totalBurned += burnAmount;
                    emit TokensBurned(from, burnAmount);
                }

                if (treasuryAmount > 0) {
                    _rawTransfer(from, address(this), treasuryAmount);
                    tokensForTreasury += treasuryAmount;
                }

                amount -= totalFees;
            }
        }

        _rawTransfer(from, to, amount);
    }

    /// @dev Bare-bones balance move with no hooks — used internally
    function _rawTransfer(address from, address to, uint256 amount) internal {
        require(_balances[from] >= amount, "ERC20: transfer amount exceeds balance");
        unchecked { _balances[from] -= amount; }
        _balances[to] += amount;
        emit Transfer(from, to, amount);
    }

    function _approve(address owner_, address spender, uint256 amount) internal {
        require(owner_  != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner_][spender] = amount;
        emit Approval(owner_, spender, amount);
    }


    function _swapBack() private {
        uint256 contractBalance   = _balances[address(this)];
        uint256 totalTokensToSwap = tokensForTreasury;

        if (contractBalance == 0 || totalTokensToSwap == 0) return;

        if (contractBalance > swapTokensAtAmount * 5) {
            contractBalance = swapTokensAtAmount * 5;
        }

        for (uint i = 0; i < activeRouters.length; i++) {
            RouterPair memory rp = routerPairs[activeRouters[i]];
            if (rp.isActive && contractBalance > 0) {
                uint256 routerShare = contractBalance / (activeRouters.length - i);
                if (routerShare > 0) {
                    _swapTokensForEth(routerShare, rp.router);
                    contractBalance -= routerShare;
                }
            }
        }

        tokensForTreasury = 0;

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            (bool ok,) = TreasuryAddress.call{value: ethBalance}("");
            require(ok, "ETH transfer to Treasury failed");
            emit FeesProcessed(ethBalance);
        }
    }

    function _swapTokensForEth(uint256 tokenAmount, IDexRouter router) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        _approve(address(this), address(router), tokenAmount);

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }


    function addRouter(address _router, address _baseToken) external onlyOwner {
        require(_router != address(0),                              "Router: zero address");
        require(address(routerPairs[_router].router) == address(0),"Router: already added");

        IDexRouter router = IDexRouter(_router);
        isRouter[_router] = true;

        address pair = IDexFactory(router.factory()).createPair(address(this), _baseToken);

        routerPairs[_router] = RouterPair({
            router:    router,
            pair:      pair,
            baseToken: _baseToken,
            isActive:  true
        });

        activeRouters.push(_router);
        _setAMMPair(pair, true);
        _setExcluded(_router, true);

        emit RouterAdded(_router, _baseToken, pair);
    }

    function removeRouter(address _router) external onlyOwner {
        require(_router != address(defaultRouter),                  "Router: cannot remove default");
        require(address(routerPairs[_router].router) != address(0),"Router: not found");

        for (uint i = 0; i < activeRouters.length; i++) {
            if (activeRouters[i] == _router) {
                activeRouters[i] = activeRouters[activeRouters.length - 1];
                activeRouters.pop();
                break;
            }
        }

        isRouter[_router] = false;
        delete routerPairs[_router];
        emit RouterRemoved(_router);
    }

    function toggleRouterActive(address _router, bool active) external onlyOwner {
        require(address(routerPairs[_router].router) != address(0), "Router: not found");
        routerPairs[_router].isActive = active;
        emit RouterActivated(_router, active);
    }

    function getActiveRouters() external view returns (address[] memory) {
        return activeRouters;
    }

    function getRouterInfo(address _router)
        external view
        returns (address pair, address baseToken, bool active)
    {
        RouterPair memory rp = routerPairs[_router];
        return (rp.pair, rp.baseToken, rp.isActive);
    }


    function enableTrading(bool _status, uint256 _deadBlocks) external onlyOwner {
        require(!tradingActive,    "Cannot re-enable trading");
        require(_deadBlocks > 0,   "Dead blocks must be > 0");

        tradingActive = _status;
        swapEnabled   = true;

        if (tradingActive && tradingActiveBlock == 0) {
            tradingActiveBlock = block.number;
            deadBlocks         = _deadBlocks;
        }

        emit EnabledTrading(tradingActive, _deadBlocks);
    }

 

    function excludeFromFees(address account, bool excluded) external onlyOwner {
        _setExcluded(account, excluded);
        emit ExcludeFromFees(account, excluded);
    }

    function isExcludedFromFees(address account) external view returns (bool) {
        return _isExcludedFromFees[account];
    }

    function updateSwapThreshold(uint256 newAmount) external onlyOwner {
        require(newAmount > 0, "Amount must be > 0");
        swapTokensAtAmount = newAmount * 1e18;
        emit UpdatedSwapThreshold(swapTokensAtAmount);
    }

    function setAutomatedMarketMakerPair(address pair, bool value) external onlyOwner {
        _setAMMPair(pair, value);
    }

    function setTreasuryAddress(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Treasury: zero address");
        TreasuryAddress = _treasury;
        emit UpdatedTreasuryAddress(_treasury);
    }

    

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount)
        external payable onlyOwner
    {
        require(address(this).balance >= ethAmount, "Insufficient ETH");
        _approve(address(this), address(defaultRouter), tokenAmount);

        defaultRouter.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, 0,
            _owner,
            block.timestamp
        );
    }


    function manualSwap() external {
        require(msg.sender == TreasuryAddress, "Only Treasury");
        uint256 tokenBalance = _balances[address(this)];
        if (tokenBalance > 0) {
            _swapping = true;
            _swapBack();
            _swapping = false;
        }
    }

    function transferForeignToken(address _token, address _to)
        external returns (bool sent)
    {
        require(_token != address(0),            "Token: zero address");
        require(msg.sender == TreasuryAddress,   "Only Treasury");
        uint256 bal = IERC20(_token).balanceOf(address(this));
        sent = IERC20(_token).transfer(_to, bal);
        emit TransferForeignToken(_token, bal);
    }

    function withdrawStuckETH() external {
        require(msg.sender == TreasuryAddress, "Only Treasury");
        uint256 bal = address(this).balance;
        require(bal > 0, "No ETH");
        (bool ok,) = TreasuryAddress.call{value: bal}("");
        require(ok, "ETH transfer failed");
        emit WithdrewStuckETH(bal);
    }

   

    function owner() public view returns (address) { return _owner; }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    function renounceOwnership() external onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    

    function getTotalBurned() external view returns (uint256) { return totalBurned; }


    function _setExcluded(address account, bool excluded) private {
        _isExcludedFromFees[account] = excluded;
    }

    function _setAMMPair(address pair, bool value) private {
        automatedMarketMakerPairs[pair] = value;
        emit SetAutomatedMarketMakerPair(pair, value);
    }

    receive() external payable {}
}


