// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * Bark-A-Lot (BARK)
 */

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
    function transferFrom(address sender,address recipient,uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract ERC20 is Context, IERC20 {
    mapping(address => uint256) internal _balances;
    mapping(address => mapping(address => uint256)) internal _allowances;

    uint256 internal _totalSupply;
    string internal _name;
    string internal _symbol;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function name() public view returns (string memory) { return _name; }
    function symbol() public view returns (string memory) { return _symbol; }
    function decimals() public pure returns (uint8) { return 18; }
    function totalSupply() public view override returns (uint256) { return _totalSupply; }
    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender,address recipient,uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: exceeds allowance");

        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }

        return true;
    }

    function _transfer(address from,address to,uint256 amount) internal virtual {
        require(from != address(0) && to != address(0), "Zero address");
        uint256 bal = _balances[from];
        require(bal >= amount, "Insufficient");

        unchecked {
            _balances[from] = bal - amount;
        }

        _balances[to] += amount;
        emit Transfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal {
        _totalSupply += amount;
        _balances[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function _approve(address owner,address spender,uint256 amount) internal {
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
}

contract Ownable is Context {
    address public owner;

    event OwnershipTransferred(address indexed prev, address indexed next);

    constructor() {
        owner = _msgSender();
        emit OwnershipTransferred(address(0), owner);
    }

    modifier onlyOwner() {
        require(owner == _msgSender(), "Not owner");
        _;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero");
        owner = newOwner;
        emit OwnershipTransferred(_msgSender(), newOwner);
    }
}

contract BARK is ERC20, Ownable {

    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 1e18;

    address public treasury;

    mapping(address => bool) public automatedMarketMakerPairs;
    mapping(address => bool) private _isExcludedFromFees;

    event SetAMMPair(address pair, bool value);
    event ExcludeFromFees(address account, bool excluded);
    event TreasuryUpdated(address treasury);

    constructor(address _treasury) ERC20("Bark-A-Lot", "BARK") {
        require(_treasury != address(0), "Invalid treasury");

        treasury = _treasury;

        // mint full supply
        _mint(msg.sender, MAX_SUPPLY);

        // exclusions
        _isExcludedFromFees[msg.sender] = true;
        _isExcludedFromFees[address(this)] = true;
        _isExcludedFromFees[_treasury] = true;
    }

    // =========================
    // CONFIG
    // =========================

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Zero");
        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }

    function excludeFromFees(address account, bool excluded) external onlyOwner {
        _isExcludedFromFees[account] = excluded;
        emit ExcludeFromFees(account, excluded);
    }

    function setAMMPair(address pair, bool value) external onlyOwner {
        automatedMarketMakerPairs[pair] = value;
        emit SetAMMPair(pair, value);
    }

    // =========================
    // TAX LOGIC
    // =========================

    function _transfer(address from, address to, uint256 amount) internal override {

        if (_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            super._transfer(from, to, amount);
            return;
        }

        uint256 fee;
        uint256 burnAmount;
        uint256 treasuryAmount;

        if (automatedMarketMakerPairs[from] || automatedMarketMakerPairs[to]) {

            fee = (amount * 3) / 100;

            burnAmount = fee / 3;              
            treasuryAmount = fee - burnAmount; 

            if (burnAmount > 0) {
                super._transfer(from, address(0xdead), burnAmount);
            }

            if (treasuryAmount > 0) {
                super._transfer(from, treasury, treasuryAmount);
            }

            amount -= fee;
        }

        super._transfer(from, to, amount);
    }
}
