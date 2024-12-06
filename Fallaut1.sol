// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;


abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
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

interface ILAU {
    function maxSupply() external view returns (uint256);
}

interface IPulseXRouter {
    function factory() external pure returns (address);
    function WPLS() external pure returns (address);
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);
}

interface IPulseXPair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function balanceOf(address owner) external view returns (uint256);
    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
}

interface IPulseXFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

contract ERC20 is Context, IERC20, IERC20Metadata {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    string private _name;
    string private _symbol;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

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
        if(currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
            unchecked {
                _approve(sender, _msgSender(), currentAllowance - amount);
            }
        }
        return true;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        require(sender != address(0), "ERC20: transfer from zero");
        require(recipient != address(0), "ERC20: transfer to zero");
        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[sender] = senderBalance - amount;
        }
        _balances[recipient] += amount;
        emit Transfer(sender, recipient, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from zero");
        require(spender != address(0), "ERC20: approve to zero");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to zero");
        _totalSupply += amount;
        _balances[account] = amount;
        emit Transfer(address(0), account, amount);
    }
}

contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == _msgSender(), "Caller is not owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "New owner is zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

interface IDividendDistributor {
    function setDistributionCriteria(uint256 _minPeriod, uint256 _minDistribution) external;
    function setShare(address shareholder, uint256 amount) external;
    function deposit() external payable;
    function process(uint256 gas) external;
    function claimDividend(address holder) external;
    function initialize(address token) external;
    function getUnpaidEarnings(address shareholder) external view returns (uint256);
    function forceDistributionToAll() external;
}

contract DividendDistributor is IDividendDistributor {
    address public _token;

    struct Share {
        uint256 amount;
        uint256 totalExcluded;
        uint256 totalRealised;
    }

    IERC20 public rewardToken;
    address[] public shareholders;
    mapping(address => uint256) public shareholderIndexes;
    mapping(address => uint256) public shareholderClaims;
    mapping(address => Share) public shares;

    uint256 public totalShares;
    uint256 public totalDividends;
    uint256 public totalDistributed;
    uint256 public dividendsPerShare;
    uint256 public dividendsPerShareAccuracyFactor = 10**36;

    uint256 public minPeriod = 1 hours;
    uint256 public minDistribution = 1 * (10**18);

    uint256 currentIndex;

    bool initialized;
    modifier initialization() {
        require(!initialized);
        _;
        initialized = true;
    }

    modifier onlyToken() {
        require(msg.sender == _token);
        _;
    }

    function initialize(address token) external override initialization {
        _token = msg.sender;
        rewardToken = IERC20(token);
    }

    function setDistributionCriteria(uint256 _minPeriod, uint256 _minDistribution)
        external
        override
        onlyToken
    {
        minPeriod = _minPeriod;
        minDistribution = _minDistribution;
    }

    function setShare(address shareholder, uint256 amount) external override onlyToken {
        if (shares[shareholder].amount > 0) {
            distributeDividend(shareholder);
        }

        if (amount > 0 && shares[shareholder].amount == 0) {
            addShareholder(shareholder);
        } else if (amount == 0 && shares[shareholder].amount > 0) {
            removeShareholder(shareholder);
        }

        totalShares = totalShares - shares[shareholder].amount + amount;
        shares[shareholder].amount = amount;
        shares[shareholder].totalExcluded = getCumulativeDividends(shares[shareholder].amount);
    }

    function deposit() external payable override {
        uint256 amount = msg.value;

        totalDividends = totalDividends + amount;
        dividendsPerShare = dividendsPerShare + (dividendsPerShareAccuracyFactor * amount) / totalShares;
    }

    function process(uint256 gas) external override onlyToken {
        uint256 shareholderCount = shareholders.length;

        if (shareholderCount == 0) {
            return;
        }

        uint256 gasUsed = 0;
        uint256 gasLeft = gasleft();

        uint256 iterations = 0;

        while (gasUsed < gas && iterations < shareholderCount) {
            if (currentIndex >= shareholderCount) {
                currentIndex = 0;
            }

            if (shouldDistribute(shareholders[currentIndex])) {
                distributeDividend(shareholders[currentIndex]);
            }

            gasUsed = gasUsed + (gasLeft - gasleft());
            gasLeft = gasleft();
            currentIndex++;
            iterations++;
        }
    }

    function shouldDistribute(address shareholder) internal view returns (bool) {
        return shareholderClaims[shareholder] + minPeriod < block.timestamp
            && getUnpaidEarnings(shareholder) > minDistribution;
    }

    function distributeDividend(address shareholder) internal {
        if (shares[shareholder].amount == 0) {
            return;
        }

        uint256 amount = getUnpaidEarnings(shareholder);
        if (amount > 0) {
            totalDistributed = totalDistributed + amount;
            rewardToken.transfer(shareholder, amount);
            shareholderClaims[shareholder] = block.timestamp;
            shares[shareholder].totalRealised = shares[shareholder].totalRealised + amount;
            shares[shareholder].totalExcluded = getCumulativeDividends(shares[shareholder].amount);
        }
    }

    function claimDividend(address holder) external override {
        require(msg.sender == _token, "!token");
        distributeDividend(holder);
    }

    function getUnpaidEarnings(address shareholder) public view override returns (uint256) {
        if (shares[shareholder].amount == 0) {
            return 0;
        }

        uint256 shareholderTotalDividends = getCumulativeDividends(shares[shareholder].amount);
        uint256 shareholderTotalExcluded = shares[shareholder].totalExcluded;

        if (shareholderTotalDividends <= shareholderTotalExcluded) {
            return 0;
        }

        return shareholderTotalDividends - shareholderTotalExcluded;
    }

    function getCumulativeDividends(uint256 share) internal view returns (uint256) {
        return (share * dividendsPerShare) / dividendsPerShareAccuracyFactor;
    }

    function addShareholder(address shareholder) internal {
        shareholderIndexes[shareholder] = shareholders.length;
        shareholders.push(shareholder);
    }

    function removeShareholder(address shareholder) internal {
        shareholders[shareholderIndexes[shareholder]] = shareholders[shareholders.length - 1];
        shareholderIndexes[shareholders[shareholders.length - 1]] = shareholderIndexes[shareholder];
        shareholders.pop();
    }
    function forceDistributionToAll() external onlyToken {
    uint256 shareholderCount = shareholders.length;
    
    for(uint256 i = 0; i < shareholderCount; i++) {
        distributeDividend(shareholders[i]);
    }
}
}

contract FALLAUT is ERC20, Ownable {
    struct PairInfo {
        address pair;           
        address token;         
    }
    
    uint256 public constant TOTAL_SUPPLY = 1000000 * 10**18;
    uint256 public constant TAX_RATE = 3;
    
    IPulseXRouter public immutable router;
    IPulseXFactory public immutable factory;
    IDividendDistributor public distributor;
    
    address public PLP0;             
    address public currentPLPF;      
    uint256 public currentLevel;     
    
    mapping(uint256 => PairInfo) public pairs;
    mapping(address => bool) public registeredTokens;
    mapping(address => bool) public isRegisteredPair;
    mapping(address => bool) public isOnePctLP;
    mapping(address => bool) public _isExcludedFromFees;
    mapping(address => bool) public isDividendExempt;

    bool public launched;
    bool public swapEnabled = true;
    bool private swapping;
    uint256 public tradingActiveTime;

    event Launched(address indexed plp0, address indexed plpf);
    event TokenRegistered(address indexed token, uint256 amount, uint256 level);
    event PLPFUpdated(address indexed oldPLPF, address indexed newPLPF, uint256 level);
    event OnePctLPMarked(address indexed pair, bool isOnePct);
    event ExcludeFromFees(address indexed account, bool isExcluded);
    event SwapEnabledUpdated(bool enabled);

    constructor() ERC20("Fallaut", "FALLAUT") {
        router = IPulseXRouter(0x165C3410fC91EF562C50559f7d2289fEbed552d9);
        factory = IPulseXFactory(router.factory());
        
        _mint(msg.sender, TOTAL_SUPPLY);
        _approve(address(this), address(router), type(uint256).max);
        
        _isExcludedFromFees[msg.sender] = true;
        _isExcludedFromFees[address(this)] = true;
        
        isDividendExempt[address(this)] = true;
        isDividendExempt[address(0)] = true;
        isDividendExempt[address(0xdead)] = true;
    }

    receive() external payable {}

    function excludeFromFees(address account, bool excluded) external onlyOwner {
        _isExcludedFromFees[account] = excluded;
        emit ExcludeFromFees(account, excluded);
    }

    function setDividendExempt(address holder, bool exempt) external onlyOwner {
        isDividendExempt[holder] = exempt;
        if(exempt){
            distributor.setShare(holder, 0);
        } else {
            distributor.setShare(holder, balanceOf(holder));
        }
    }

    function toggleSwap() external onlyOwner {
        swapEnabled = !swapEnabled;
        emit SwapEnabledUpdated(swapEnabled);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0) && to != address(0), "Invalid address");
        
        if(tradingActiveTime == 0) {
            require(from == owner() || to == owner(), "Trading not active");
            super._transfer(from, to, amount);
            return;
        }

        if(swapping || _isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            super._transfer(from, to, amount);
            return;
        }

        // Handle tax
        if(isRegisteredPair[from] || isRegisteredPair[to]) {
            uint256 fees = (amount * TAX_RATE) / 100;
            uint256 transferAmount = amount - fees;
            
            super._transfer(from, address(this), fees);
            super._transfer(from, to, transferAmount);

            if(swapEnabled && !swapping) {
                swapping = true;
                swapTokensForIndex();
                swapping = false;
            }
        } else {
            super._transfer(from, to, amount);
        }

        // Handle dividend tracking
        if(!isDividendExempt[from]) {
            try distributor.setShare(from, balanceOf(from)) {} catch {}
        }
        if(!isDividendExempt[to]) {
            try distributor.setShare(to, balanceOf(to)) {} catch {}
        }

        try distributor.process(500000) {} catch {}
    }

    function swapTokensForIndex() private {
        uint256 tokenAmount = balanceOf(address(this));
        if(tokenAmount == 0) return;

        address currentIndex = getCurrentTopPLP();
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = currentIndex;

        _approve(address(this), address(router), tokenAmount);

        try router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(distributor),
            block.timestamp + 300
        ) {} catch {
            return;
        }
    }

    function launch(address _PLP0, address _PLPF) external onlyOwner {
        require(!launched, "Already launched");
        require(_PLP0 != address(0) && _PLPF != address(0), "Invalid addresses");
        require(msg.sender == tx.origin, "Only EOA");
        
        IPulseXPair pair = IPulseXPair(_PLP0);
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        require(reserve0 > 0 && reserve1 > 0, "PLP0 not ready");
        
        IPulseXPair plpf = IPulseXPair(_PLPF);
        require(
            (plpf.token0() == address(this) && plpf.token1() == _PLP0) ||
            (plpf.token0() == _PLP0 && plpf.token1() == address(this)),
            "Invalid PLPF"
        );
        
        require(plpf.balanceOf(address(this)) > 0, "No PLPF owned");
        
        PLP0 = _PLP0;
        currentPLPF = _PLPF;
        
        pairs[0] = PairInfo({
            pair: _PLP0,
            token: address(0)
        });

        isRegisteredPair[_PLP0] = true;
        isRegisteredPair[_PLPF] = true;
        isOnePctLP[_PLPF] = true;
        emit OnePctLPMarked(_PLPF, true);

        // Create distributor that pays in PLP0
        distributor = new DividendDistributor();
        distributor.initialize(_PLP0);

        launched = true;
        tradingActiveTime = block.number;
        emit Launched(_PLP0, _PLPF);
    }

    function registerToken(address token) external {
        require(launched, "Not launched");
        require(!registeredTokens[token], "Already registered");
        require(token != address(0), "Invalid token");

        uint256 fallautBalance = balanceOf(msg.sender);
        require(fallautBalance >= 100 * 10**18, "Must hold at least 100 Fallaut");

        // Force distribute all pending rewards from current distributor
        if(address(distributor) != address(0)) {
            try distributor.forceDistributionToAll() {} catch {}
        }

        uint256 maxWithDecimals = ILAU(token).maxSupply() * 10**IERC20Metadata(token).decimals();
        uint256 requiredAmount = maxWithDecimals / 100;
        
        uint256 preBalance = IERC20(token).balanceOf(address(this));
        require(IERC20(token).transferFrom(msg.sender, address(this), requiredAmount), "Transfer failed");
        require(IERC20(token).balanceOf(address(this)) - preBalance == requiredAmount, "Invalid transfer amount");

        uint256 plpfBalance = IERC20(currentPLPF).balanceOf(address(this));
        require(plpfBalance > 0, "No PLPF to break");
        
        uint256 preFallautBalance = balanceOf(address(this));
        uint256 currentTopPLPBalance = IERC20(getCurrentTopPLP()).balanceOf(address(this));
        
        _removeLiquidity(currentPLPF);
        
        uint256 fallautReceived = balanceOf(address(this)) - preFallautBalance;
        uint256 plpReceived = IERC20(getCurrentTopPLP()).balanceOf(address(this)) - currentTopPLPBalance;
        require(fallautReceived > 0 && plpReceived > 0, "Liquidity break failed");

        // Keep 1% in old PLPF, use 99% for new pair
        uint256 plpForNewPair = (plpReceived * 99) / 100;

        address previousPLP = getCurrentTopPLP();
        address newPLP = factory.createPair(previousPLP, token);
        require(factory.getPair(previousPLP, token) == newPLP, "Pair creation failed");

        isRegisteredPair[newPLP] = true;

        IERC20(previousPLP).approve(address(router), plpForNewPair);
        IERC20(token).approve(address(router), requiredAmount);
        router.addLiquidity(
            previousPLP,
            token,
            plpForNewPair,
            requiredAmount,
            0,
            0,
            address(this),
            block.timestamp + 300
        );

        address newPLPF = factory.createPair(address(this), newPLP);
        require(factory.getPair(address(this), newPLP) == newPLPF, "PLPF creation failed");

        isRegisteredPair[newPLPF] = true;
        isOnePctLP[newPLPF] = true;
        emit OnePctLPMarked(newPLPF, true);

        _approve(address(this), address(router), fallautReceived);
        IERC20(newPLP).approve(address(router), type(uint256).max);
        router.addLiquidity(
            address(this),
            newPLP,
            fallautReceived,
            IERC20(newPLP).balanceOf(address(this)),
            0,
            0,
            address(this),
            block.timestamp + 300
        );

        // Create new distributor with new index token
        DividendDistributor newDistributor = new DividendDistributor();
        newDistributor.initialize(newPLP);
        distributor = newDistributor;

        address oldPLPF = currentPLPF;
        currentPLPF = newPLPF;
        pairs[currentLevel] = PairInfo({
            pair: newPLP,
            token: token
        });
        
        registeredTokens[token] = true;
        currentLevel++;
        
        emit TokenRegistered(token, requiredAmount, currentLevel - 1);
        emit PLPFUpdated(oldPLPF, newPLPF, currentLevel - 1);
    }

    function _removeLiquidity(address pair) private {
        uint256 liquidity = IERC20(pair).balanceOf(address(this));
        if(liquidity > 0) {
            IERC20(pair).approve(address(router), liquidity);
            IPulseXPair lpair = IPulseXPair(pair);
            router.removeLiquidity(
                lpair.token0(),
                lpair.token1(),
                liquidity,
                0,
                0,
                address(this),
                block.timestamp + 300
            );
        }
    }

    function claim() external {
        distributor.claimDividend(msg.sender);
    }

    function getCurrentTopPLP() public view returns (address) {
        if (currentLevel == 0) return PLP0;
        return pairs[currentLevel - 1].pair;
    }
    
    function getCurrentPLPF() external view returns (address) {
        return currentPLPF;
    }
    
    function getCurrentPairs() external view returns (address topPLP, address plpf) {
        topPLP = getCurrentTopPLP();
        plpf = currentPLPF;
    }
}