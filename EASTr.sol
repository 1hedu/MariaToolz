// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function allowance(address, address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IERC20Metadata is IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
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
            require(currentAllowance >= amount);
            unchecked { _approve(sender, _msgSender(), currentAllowance - amount); }
        }
        return true;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        require(sender != address(0));
        require(recipient != address(0));
        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount);
        unchecked {
            _balances[sender] = senderBalance - amount;
        }
        _balances[recipient] += amount;
        emit Transfer(sender, recipient, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0));
        require(spender != address(0));
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _initialTransfer(address to, uint256 amount) internal virtual {
        _balances[to] = amount;
        _totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }
}

contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = _msgSender();
        emit OwnershipTransferred(address(0), _msgSender());
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == _msgSender());
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0));
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

interface IDividendDistributor {
    function setShare(address,uint256,bool) external;
    function deposit() external payable;
    function process() external;
    function initialize() external;
    function initialized() external view returns(bool);
    function setDistributionCriteria(uint256,uint256,uint256) external;
    function getUnpaidEarnings(address) external view returns(uint256);
    function getPaidDividends(address) external view returns(uint256);
    function getTotalDividends() external view returns(uint256);
    function getTotalDistributed() external view returns(uint256);
    function migrate(address) external;
    function claimDividend(address) external;
    function countShareholders() external view returns(uint256);
    function getClaimTime(address) external view returns(uint256);
}

interface IDexRouter {
    function factory() external pure returns(address);
    function WPLS() external pure returns(address);
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256,uint256,address[] calldata,address,uint256
    ) external;
    function addLiquidityETH(
        address,uint256,uint256,uint256,address,uint256
    ) external payable returns(uint256,uint256,uint256);
    function addLiquidity(
        address,address,uint256,uint256,uint256,uint256,address,uint256
    ) external returns(uint256,uint256,uint256);
}

interface IDexFactory {
    function createPair(address,address) external returns(address);
}


contract EASTr is ERC20, Ownable {
    mapping(address => uint256) private _protection;
    mapping(address => bool) private _noFees;
    mapping(address => bool) private _noDivs;
    mapping(address => bool) private _pairs;

    IDexRouter public immutable dexRouter;
    IDividendDistributor public distributor;
    address public lpPair;
    address public taxCollector;

    uint8 private constant DECIMALS = 9;
    uint256 private constant DECIMAL_FACTOR = 10 ** 9;
    uint256 public swapAt;
    uint256 public maxSwap;
    uint256 public taxSplit = 100;
    uint256 public tradingActiveTime;
    uint256 public taxFee = 1;

    bool private _swapping;
    bool public swapOn = true;
    bool public autoProcess = true;
    bool public protectionOff;

    event SetPair(address,bool);
    event ExcludeFromFees(address,bool);

    constructor(
        string memory name, 
        string memory ticker, 
        uint256 supply,
        address reward
    ) ERC20(name, ticker) {
        address router = 0x165C3410fC91EF562C50559f7d2289fEbed552d9;
        dexRouter = IDexRouter(router);

        _approve(msg.sender, router, type(uint256).max);
        _approve(address(this), router, type(uint256).max);

        uint256 tSupply = supply * DECIMAL_FACTOR;
        swapAt = tSupply / 1000000;
        maxSwap = (tSupply * 5) / 1000;

        _noFees[msg.sender] = true;
        _noFees[address(this)] = true;
        _noDivs[router] = true;
        _noDivs[address(this)] = true;
        _noDivs[address(0xdead)] = true;

        _initialTransfer(msg.sender, tSupply);

        DividendDistributor dist = new DividendDistributor(reward);
        dist.initialize();
        distributor = dist;
    }

    receive() external payable {}

    function decimals() public pure override returns(uint8) { return DECIMALS; }

    function updateSwapTokens(uint256 at, uint256 max) external onlyOwner {
        require(max <= totalSupply() / 100);
        swapAt = at;
        maxSwap = max;
    }
    
    function setTaxFee(uint256 _taxFee) external onlyOwner {
    require(_taxFee > 0 && _taxFee <= 100, "Tax fee must be between 1 and 100");
    taxFee = _taxFee;
    }

    function setTaxCollector(address wallet) external onlyOwner {
        taxCollector = wallet;
    }

    function toggleSwap() external onlyOwner { swapOn = !swapOn; }
    function toggleProcess() external onlyOwner { autoProcess = !autoProcess; }

    function setPair(address pair, bool value) external {
        require(pair != lpPair && (msg.sender == owner() || msg.sender == taxCollector));
        _pairs[pair] = value;
        _noDivs[pair] = true;
        emit SetPair(pair, value);
    }

    function setSplit(uint256 split) external onlyOwner {
        require(split <= 100);
        taxSplit = split;
    }

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        _noFees[account] = excluded;
        emit ExcludeFromFees(account, excluded);
    }

    function setDividendExempt(address holder, bool exempt) public onlyOwner {
        _noDivs[holder] = exempt;
        if(exempt) distributor.setShare(holder, 0, true);
        else distributor.setShare(holder, balanceOf(holder), false);
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        if(from == address(0) || to == address(0)) revert();

        if(tradingActiveTime == 0) {
            require(_noFees[from] || _noFees[to]);
            super._transfer(from, to, amount);
            return;
        }

        if(!_noFees[from] && !_noFees[to]) {
            uint256 fee = amount * taxFee / 100;
            if(fee > 0) {
                super._transfer(from, address(this), fee);
                if(swapOn && !_swapping && _pairs[to]) {
                    _swapping = true;
                    swapBack(amount);
                    _swapping = false;
                }
                amount -= fee;
            }
        }

        super._transfer(from, to, amount);
        if(autoProcess) try distributor.process() {} catch {}

        require(_protection[from] == 0 || to == owner());

        if(!_noDivs[from]) try distributor.setShare(from, balanceOf(from), false) {} catch {}
        if(!_noDivs[to]) try distributor.setShare(to, balanceOf(to), false) {} catch {}
    }

    function swapTokensForEth(uint256 tokens) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = dexRouter.WPLS();
        dexRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokens, 0, path, address(this), block.timestamp
        );
    }

    function swapBack(uint256 amt) private {
        uint256 ts = balanceOf(address(this));
        if(ts < swapAt || ts > amt || ts == 0) return;
        if(ts > maxSwap) ts = maxSwap;

        uint256 pre = address(this).balance;
        swapTokensForEth(ts);
        uint256 got = address(this).balance - pre;

        if(got > 0) {
            uint256 split = taxSplit * got / 100;
            if(split > 0) try distributor.deposit{value: split}() {} catch {}
            if(got > split) {
                (bool s,) = taxCollector.call{value: address(this).balance}("");
                require(s);
            }
        }
    }
function addLP(uint256 tokens, uint256 paired, address with) external payable onlyOwner {
        require(tokens > 0);
        address eth = dexRouter.WPLS();
        lpPair = IDexFactory(dexRouter.factory()).createPair(with, address(this));
        _pairs[lpPair] = true;
        _noDivs[lpPair] = true;

        super._transfer(msg.sender, address(this), tokens * DECIMAL_FACTOR);

        if(with == eth) {
            dexRouter.addLiquidityETH{value: msg.value}(
                address(this),balanceOf(address(this)),0,0,msg.sender,block.timestamp
            );
        } else {
            IERC20(with).transferFrom(msg.sender, address(this), paired);
            dexRouter.addLiquidity(
                address(this),with,balanceOf(address(this)),
                IERC20(with).balanceOf(address(this)),0,0,msg.sender,block.timestamp
            );
        }
    }

    function launch() external onlyOwner {
        require(tradingActiveTime == 0);
        tradingActiveTime = block.number;
    }

    function setDistributor(address newDist, bool migrate) public onlyOwner {
        if(migrate) distributor.migrate(newDist);
        distributor = IDividendDistributor(newDist);
        distributor.initialize();
    }

    function setDistributionCriteria(uint256 minP, uint256 minD, uint256 claimAfter) external onlyOwner {
        distributor.setDistributionCriteria(minP, minD, claimAfter);
    }

    function getStats(address wallet) external view returns(
        uint256 reward,
        uint256 claimed,
        uint256 nextClaim
    ) {
        return (
            distributor.getUnpaidEarnings(wallet),
            distributor.getPaidDividends(wallet),
            distributor.getClaimTime(wallet)
        );
    }

    function claim() external {
        distributor.claimDividend(msg.sender);
    }

    function airdrop(address[] calldata to, uint256[] calldata amt, bool divs) external onlyOwner {
        require(to.length == amt.length);
        for(uint256 i; i < to.length;) {
            super._transfer(msg.sender, to[i], amt[i] * DECIMAL_FACTOR);
            if(divs) distributor.setShare(to[i], amt[i] * DECIMAL_FACTOR, false);
            unchecked { ++i; }
        }
    }

    function protect(address[] calldata w, uint256 e) external onlyOwner {
        if(e > 0) require(!protectionOff);
        for(uint256 i; i < w.length;) {
            _protection[w[i]] = e;
            unchecked { ++i; }
        }
    }

    function disableProtection() external onlyOwner {
        protectionOff = true;
    }
}

contract DividendDistributor is IDividendDistributor {
    bool private init;
    address public _token;
    IERC20 public immutable reward;
    
    struct Share {
        uint256 amount;
        uint256 excluded;
        uint256 realized;
    }

    address[] sholders;
    mapping(address => uint256) indices;
    mapping(address => uint256) claims;
    mapping(address => Share) shares;
    
    uint256 public totalShares;
    uint256 public totalDividends;
    uint256 public totalDistributed;
    uint256 public divPerShare;
    uint256 constant ACCURACY = 10**36;
    
    uint256 public minPeriod = 30 minutes;
    uint256 public minDist = 1;
    uint256 public gas = 500000;
    uint256 public current;
    
    modifier onlyToken {
        require(msg.sender == _token);
        _;
    }
    
    constructor(address rwd) { reward = IERC20(rwd); }
    
    function initialize() external override {
        require(!init);
        _token = msg.sender;
        init = true;
    }
    
    function initialized() external view override returns(bool) { return init; }
    
    function setShare(address sh, uint256 amt, bool) external override onlyToken {
        if(amt > 0 && shares[sh].amount == 0){
            indices[sh] = sholders.length;
            sholders.push(sh);
            shares[sh].excluded = getCumulativeDividends(amt);
            claims[sh] = block.timestamp;
        } else if(amt == 0 && shares[sh].amount > 0){
            sholders[indices[sh]] = sholders[sholders.length-1];
            indices[sholders[sholders.length-1]] = indices[sh];
            sholders.pop();
        }
        totalShares = totalShares - shares[sh].amount + amt;
        shares[sh].amount = amt;
        shares[sh].excluded = getCumulativeDividends(amt);
    }

    function deposit() external payable override {
        totalDividends += msg.value;
        if(totalShares > 0) {
            divPerShare = divPerShare == 0 
                ? ACCURACY * totalDividends / totalShares 
                : divPerShare + (ACCURACY * msg.value / totalShares);
        }
    }

    function process() external override {
        uint256 count = sholders.length;
        if(count == 0) return;
        
        uint256 used;
        uint256 left = gasleft();
        uint256 iters;
        
        while(used < gas && iters < count) {
            if(current >= count) current = 0;
            
            if(shouldDistribute(sholders[current])){
                distribute(sholders[current]);
            }
            
            used += left - gasleft();
            left = gasleft();
            current++;
            iters++;
        }
    }

    function shouldDistribute(address sh) internal view returns(bool) {
        return claims[sh] + minPeriod < block.timestamp
            && getUnpaidEarnings(sh) > minDist;
    }

    function distribute(address sh) internal {
        if(shares[sh].amount == 0) return;
        
        uint256 amt = getUnpaidEarnings(sh);
        if(amt > 0) {
            totalDistributed += amt;
            claims[sh] = block.timestamp;
            shares[sh].realized += amt;
            shares[sh].excluded = getCumulativeDividends(shares[sh].amount);
            payable(sh).transfer(amt);
        }
    }

    function claimDividend(address sh) external override onlyToken {
        require(shouldDistribute(sh));
        distribute(sh);
    }

    function migrate(address newDist) external override onlyToken {
        require(!IDividendDistributor(newDist).initialized());
        payable(newDist).transfer(address(this).balance);
    }

    function getUnpaidEarnings(address sh) public view override returns(uint256) {
        if(shares[sh].amount == 0) return 0;
        uint256 sr = getCumulativeDividends(shares[sh].amount);
        uint256 ex = shares[sh].excluded;
        if(sr <= ex) return 0;
        return sr - ex;
    }
    
    function getCumulativeDividends(uint256 share) internal view returns(uint256) {
        return share == 0 ? 0 : (share * divPerShare) / ACCURACY;
    }
    
    function setDistributionCriteria(uint256 mp, uint256 md, uint256 g) external override onlyToken {
        minPeriod = mp;
        minDist = md;
        gas = g;
    }
    
    function getClaimTime(address sh) external view override returns(uint256) {
        uint256 t = claims[sh] + minPeriod;
        return t <= block.timestamp ? 0 : t - block.timestamp;
    }

    function getPaidDividends(address sh) external view override returns(uint256) {
        return shares[sh].realized;
    }

    function getTotalDividends() external view override returns(uint256) {
        return totalDividends;
    }

    function getTotalDistributed() external view override returns(uint256) {
        return totalDistributed;
    }

    function countShareholders() external view override returns(uint256) {
        return sholders.length;
    }
}
