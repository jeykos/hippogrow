// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9; 

import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/utils/Context.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/Strings.sol';

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IUniswapV2Router02 {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
     function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
}

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}


contract HippoGrow is Context, IERC20, Ownable
{
    // Token info
    string private constant Name = "HippoGrow";
    string private constant Symbol = "HIPPO"; 
    uint8 private constant Decimals = 18;
    uint256 private TotalSupply = 100_000_000 * 10**Decimals;
    uint256 private constant MAX = ~uint256(0);
    uint256 private ReflactionaryTotal = (MAX - (MAX % TotalSupply));

    // Movidas del swap de los panqueques 
    IUniswapV2Router02 public UniswapV2Router;
    address public PancakeSwapAddress;

    //antisnipers
    uint256 public liqAddedBlockNumber;
    uint256 public blocksToWait = 0;

    // Important addresses
    address payable private DevAddress = payable(0x2e148BF3d328D492d69FB60F7a4dC3b77622DF6E); 
    address payable private MarketingAddress = payable(0x4a9e5A0202652D728f4fF8B6791922179C502467);
    address payable private BurnAddress = payable(0x000000000000000000000000000000000000dEaD); 

    // Otras cosas de config
    uint256 private HardCap = TotalSupply / 66;
    uint256 private HardCapBuy = HardCap;
    uint256 private HardCapSell = HardCap;

    // Wallet handling zone
    mapping (address => uint256) private BalancesRefraccionarios;
    mapping (address => uint256) private BalancesReales;
    mapping (address => mapping (address => uint256)) private Allowances;
    mapping (address => bool) private Bots;


    mapping (address => bool) private WalletsExcludedFromFee;
    mapping (address => bool) private WalletsExcludedFromHardCap;
    mapping (address => bool) public AutomatedMarketMakerPairs;

    // Some cool statistics
    uint256 public TotalFee;
    uint256 public TotalSwapped;
    uint256 private TotalTokenBurn;
    
    // Historias del swap.
    bool private InSwap = false;
    bool private SwapEnabled = true; 

    // Cool trick para controlar cuando estamos swapeando
    modifier swaping {
        InSwap = true;
        _;
        InSwap = false;
    }

    uint256 private MarketingDistributionPct = 44; // 44% of taxed tokens are for mkt, becuase tax is 4% for mkt
    uint256 private DevDistributionPct = 33; // 33 % of taxed tokens are for Dev, because tax is 3% for dev
    uint256 private LPDistributionPct = 23; // 23% of taxed tokens are for LP, because tax is 2% for LP

    uint256 private LiquidityThreshold = 1 * 10 ** Decimals;

    // El pollo menciona algo de que usa las structs para evitar el error de `stack too deep` que no se que es, pero por si acaso, copy paste ma fren
    // Aunque, tambien te digo, el pavo se crea 2 structs que contienen exactmante los mismos tipos, focking n00b.
    struct TaxRates
    {
        uint256 BurnTax;
        uint256 LiquidityTax;
        uint256 MarketingTax;
        uint256 DevelopmentTax;
        uint256 RewardTax;
        string TaxPresetName;
    }
    
    
    struct TransactionFees
    {
        uint256 TransactionFee;
        uint256 BurnFee;
        uint256 DevFee;
        uint256 MarketingFee;
        uint256 LiquidityFee;
        uint256 TransferrableFee;
        uint256 TotalFee;
    }


    TaxRates public BuyingTaxes =
        TaxRates({
            RewardTax: 0, 
            BurnTax: 0, 
            DevelopmentTax: 3, 
            MarketingTax: 4, 
            LiquidityTax: 2,
            TaxPresetName: "Buying" 
        });

    TaxRates public SellTaxes =
        TaxRates({
            RewardTax: 0, 
            BurnTax: 0, 
            DevelopmentTax: 3, 
            MarketingTax: 4, 
            LiquidityTax: 2,
            TaxPresetName: "Selling" 
        });

    TaxRates public AppliedRatesPercentage = BuyingTaxes;


    TransactionFees private AccumulatedFeeForDistribution = TransactionFees({
            DevFee: 0, 
            MarketingFee: 0, 
            LiquidityFee: 0,
            BurnFee:0,
            TransferrableFee: 0,
            TotalFee: 0,
            TransactionFee: 0
        });


    // Eventos y tal
    event setDevAddress(address indexed previous, address indexed adr);
    event setMktAddress(address indexed previous, address indexed adr);
    event LiquidityAdded(uint256 tokenAmount, uint256 ETHAmount);
    event TreasuryAndDevFeesAdded(uint256 devFee, uint256 treasuryFee);
    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
    event BlacklistedUser(address botAddress, bool indexed value);
    event MaxWalletAmountUpdated(uint256 amount);
    event ExcludeFromMaxWallet(address account, bool indexed isExcluded);
    event SwapAndLiquifyEnabledUpdated(bool _enabled);
    

    constructor(address swap)
    {
       // Creando la pareja en el cambio de panqueques
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(swap);
        UniswapV2Router = _uniswapV2Router;

        PancakeSwapAddress = IUniswapV2Factory(UniswapV2Router.factory()).createPair(address(this), UniswapV2Router.WETH());

        AutomatedMarketMakerPairs[PancakeSwapAddress] = true;
        
        WalletsExcludedFromFee[owner()] = true;
        WalletsExcludedFromFee[address(this)] = true;
        WalletsExcludedFromFee[DevAddress] = true;
        WalletsExcludedFromFee[MarketingAddress] = true;
        WalletsExcludedFromFee[swap] = true;
        
        // Excluyendo del hard cap
        WalletsExcludedFromHardCap[owner()] = true;
        WalletsExcludedFromHardCap[address(this)] = true;
        WalletsExcludedFromHardCap[DevAddress] = true;
        WalletsExcludedFromHardCap[MarketingAddress] = true;
        WalletsExcludedFromHardCap[PancakeSwapAddress] = true;
        WalletsExcludedFromHardCap[swap] = true;

        // To pa mi
        BalancesRefraccionarios[_msgSender()] = ReflactionaryTotal;

        // Aprobando la wea del swapper
        _approve(address(this), address(UniswapV2Router), ~uint256(0));

        // Notificando que to pa mi.
        emit Transfer(address(0x0000000000000000000000000000000000000000), _msgSender(), TotalSupply);
    }

    function ChangeTaxes(uint256 rewardTax, uint256 mktTax, uint256 devTax, uint256 lpTax, bool buying) public onlyOwner
    {
        if(buying)
        {
            BuyingTaxes.RewardTax = rewardTax;
            BuyingTaxes.MarketingTax = mktTax;
            BuyingTaxes.DevelopmentTax = devTax;
            BuyingTaxes.LiquidityTax = lpTax;
        }
        else
        {
            SellTaxes.RewardTax = rewardTax;
            SellTaxes.MarketingTax = mktTax;
            SellTaxes.DevelopmentTax = devTax;
            SellTaxes.LiquidityTax = lpTax;
        }
    }


    function AdjustMaxHardCap(uint256 newHardCap) public onlyOwner
    {
        HardCap = newHardCap;
    }

    function AdjustMaxTxSell(uint256 maxTxSell) public onlyOwner
    {
        HardCapSell = maxTxSell;
    }   

    function AdjustMaxTxBuy(uint256 mxTxBuy) public onlyOwner
    {
        HardCapBuy = mxTxBuy;
    }

    function SwapPct(uint256 pct) public onlyOwner
    {
        uint256 balance = (balanceOf(address(this)) * pct) / 100;
        if(balance > 0)
        {
            uint256 tokensForLP = (balance * LPDistributionPct)/100;
            uint256 tokensForLiquidity = tokensForLP / 2;
            uint256 tokensToSwap = balance - tokensForLP;

            swapTokensForETH(tokensToSwap);

            uint256 contractBalance = address(this).balance;

            uint256 devShare = (contractBalance* DevDistributionPct)/100;
            uint256 mktShare = (contractBalance * MarketingDistributionPct)/100;

            DevAddress.transfer(devShare);
            MarketingAddress.transfer(mktShare);

            uint256 eth = address(this).balance;

           UniswapV2Router.addLiquidityETH{value: address(this).balance}(
                address(this),
                tokensForLiquidity,
                0, // slippage is unavoidable
                0, // slippage is unavoidable
                DevAddress,
                block.timestamp
            );
           
            AccumulatedFeeForDistribution.LiquidityFee = 0;
            AccumulatedFeeForDistribution.DevFee = 0;
            AccumulatedFeeForDistribution.MarketingFee = 0;

            TotalSwapped += tokensForLiquidity;


            emit LiquidityAdded(tokensForLiquidity, eth);
        }
    }

    // Funciones para cambiar las wallets de los VIP
    function ChangeExcludeFromFeeToForWallet(address add, bool isExcluded) public onlyOwner 
    {
        WalletsExcludedFromFee[add] = isExcluded;
    }

    function IsWalletExcludedFromFee(address targetAddress) public view returns(bool)
    {
        return WalletsExcludedFromFee[targetAddress];
    }

    function ChangeDevAddress(address payable newDevAddress) public onlyOwner 
    {
        address oldAddress = DevAddress;
        emit setDevAddress(oldAddress, newDevAddress);	
        ChangeExcludeFromFeeToForWallet(DevAddress, false); // Excluyendo la wallet antigua, que se joda ese cabron
        DevAddress = newDevAddress;
        ChangeExcludeFromFeeToForWallet(DevAddress, true);  // Incluyendo a la nueva
    }

    function ChangeMarketingAddress(address payable marketingAddress) public onlyOwner 
    {
        address oldAddress = MarketingAddress;
        emit setMktAddress(oldAddress, marketingAddress);
        ChangeExcludeFromFeeToForWallet(MarketingAddress, false); // Excluyendo la wallet antigua, que se joda ese cabron
        MarketingAddress = marketingAddress;
        ChangeExcludeFromFeeToForWallet(MarketingAddress, true);  // Incluyendo a la nueva
    }


    function totalSupply() public view override returns (uint256) 
    {
        return TotalSupply;
    }

    function decimals() public pure returns (uint8) 
    {
        return Decimals;
    }

    function symbol() public pure returns (string memory) 
    {
        return Symbol;
    }


    function name() public pure returns (string memory) 
    {
        return Name;
    }

    function getOwner() external view returns (address)
    {
        return owner();
    }


    function totalBurn() public view returns (uint256) 
    {
        return TotalTokenBurn;
    }

    function balanceOf(address account) public view override returns (uint256) 
    {
        return tokenFromReflection(BalancesRefraccionarios[account]);
    }

    function allowance(address owner, address spender) public view override returns (uint256)
    {
        return Allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool)
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transfer(address recipient, uint256 amount) public override returns (bool)
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) 
    {
        uint256 currentAllowance = allowance(sender,_msgSender());
        require(currentAllowance >= amount, "BEP20: transfer amount exceeds allowance");
        _transfer(sender, recipient, amount);
        
        unchecked 
        {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }

        return true;
    }

    // Funciones para modificar  las lista de wallets
    // Funcion para banear a una wallet de usar el contrato (a.k.a decir que es un bot/apestao)
    // Esto lo tiene 100million
    function MarkBot(address targetAddress, bool isBot) public onlyOwner 
    {
        Bots[targetAddress] = isBot;
        emit BlacklistedUser(targetAddress, isBot);
    }

    function IsBot(address targetAddress) public view returns(bool)
    {
        return Bots[targetAddress];
    }

    function ChangeExclusionFromHardCap(address targetAddress, bool isExcluded) public onlyOwner
    {
        WalletsExcludedFromHardCap[targetAddress] = isExcluded;
        emit ExcludeFromMaxWallet(targetAddress, isExcluded);
    }

    function IsExcludedFromHardCap(address targetAddress) public view returns(bool)
    {
        return WalletsExcludedFromHardCap[targetAddress];
    }

    // Funcion para setear una address para que pueda hacer tradeo automatico
    function setAutomatedMarketMakerPair(address _pair, bool value) external onlyOwner
    {
        require( AutomatedMarketMakerPairs[_pair] != value,"Automated market maker pair is already set to that value");
        AutomatedMarketMakerPairs[_pair] = value;
        ChangeExclusionFromHardCap(_pair, value);
        emit SetAutomatedMarketMakerPair(_pair, value);
    }

    // Funciones para manipular el allowance
    function _approve(address owner, address spender, uint256 amount) private 
    {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        Allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool)
    {
        _approve(_msgSender(), spender, Allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool)
    {
        uint256 currentAllowance = Allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked 
        {
            _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        }

        return true;
    }


    // Funciones de transferencia
    function _transfer(address from, address to, uint256 amount) private 
    {
        if (liqAddedBlockNumber == 0 && AutomatedMarketMakerPairs[to]) 
        {
            liqAddedBlockNumber = block.number;
        }

        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(!IsBot(from), "ERC20: address blacklisted (bot)");
        require(amount > 0, "Transfer amount must be greater than zero");
        require(amount <= balanceOf(from), "You are trying to transfer more than your balance");

        bool takeFee =  !(IsWalletExcludedFromFee(from) || IsWalletExcludedFromFee(to));

        if (takeFee) 
        {
            // Comprobando si el emisor de la transaccion es un trade automagico, a.k.a swap
            if (AutomatedMarketMakerPairs[from]) 
            {
                // Comprobando si el numero del bloque coincide con la secuencia actual, si no, 
                // a la mierda el address, porque es un bot tratando de hacer transacciones fake
                // a un address suya, probablemente, asique le baneamos su address en vez de la del
                // bot, jijijiji 
                if (block.number < liqAddedBlockNumber + blocksToWait) 
                {
                    MarkBot(to, true);
                }

                // Si, el origen es el address de la transaccion, estamos sacando tokens del pool. Aplicamos el hard cap de compra
                AppliedRatesPercentage = BuyingTaxes;
                require(amount <= HardCapBuy, "amount must be <= maxTxAmountBuy" );
            } 
            else 
            {
                // Si, la transferencia la inicia un address que no es de trading, aplicamos rates de venta (o transferencia entre peers)
                AppliedRatesPercentage = SellTaxes;
                require(amount <= HardCapSell,"amount must be <= maxTxAmountSell");
            }
        }

        // Repartir lo que ya hay si no estamos interactuando con el pair
        if (
            !InSwap &&
            !AutomatedMarketMakerPairs[from] &&
            SwapEnabled &&
            from != owner() && 
            to != owner() &&
            from != address(UniswapV2Router)
        ) {
            //add liquidity
            swapAndLiquify();
        }

       _tokenTransfer(from, to, amount, takeFee);
    }

    // This method is responsible for taking all fee, if takeFee is true
    function _tokenTransfer(address sender, address recipient, uint256 cantidadBruta, bool takeFee) private 
    {
        
        (uint256 cantidadNeta, 
        uint256 cantidadBrutaRefracionaria, 
        uint256 cantidadNetaRefracionaria, 
        TransactionFees memory feesReales, 
        TransactionFees memory feesRefracionarios) = GenerarFeesYCantidadesATransferir(cantidadBruta, takeFee);

               // Comprobando que el receptor de la transferencia no supere el hard cap de tokens
        require(WalletsExcludedFromHardCap[recipient] || 
                (balanceOf(recipient) + cantidadNeta) <= HardCap,
                "Recipient cannot hold more than maxWalletAmount"); 
    
       // Se siguen actualizando los valore reflaccionarios en caso de que las wallets 
        // sean reincluidas en las recompensas de nuevo
        BalancesRefraccionarios[sender] -= cantidadBrutaRefracionaria;
        BalancesRefraccionarios[recipient] += cantidadNetaRefracionaria;

       // Tasas, bieeeeeennnn. Sumar cositas para repartir despues.
        if (takeFee) 
        {
           
            ReflactionaryTotal -= feesRefracionarios.TransactionFee;
            TotalFee += feesReales.TransactionFee;

            AccumulateFee(feesReales, feesRefracionarios);
            // Quemando tokens
            TotalTokenBurn += feesReales.BurnFee;
            BalancesRefraccionarios[BurnAddress] += feesRefracionarios.BurnFee;

            // Emitiendo enventos para reflejar las acciones realizadas
            emit Transfer(address(this), BurnAddress, feesReales.BurnFee);
            emit Transfer(sender, address(this), feesReales.TransferrableFee);
        }
       
        emit Transfer(sender, recipient, cantidadNeta);
    }

    function GenerarFeesYCantidadesATransferir(uint256 cantidadBruta, bool aplicarImpuestos) private view returns(
        uint256 cantidadNeta, 
        uint256 cantidadBrutaRefracionaria,
        uint256 cantidadNetaRefracionaria, 
        TransactionFees memory feesReales, 
        TransactionFees memory feesRefracionarios)
    {
        (feesReales, feesRefracionarios) = CalcularTasasRealesYRefracionarias(cantidadBruta, aplicarImpuestos);
        cantidadNeta = cantidadBruta - feesReales.TotalFee;
        cantidadBrutaRefracionaria =  cantidadBruta * GetConversionRate();
        cantidadNetaRefracionaria = cantidadBrutaRefracionaria - feesRefracionarios.TotalFee;
    }


    function CalcularTasasRealesYRefracionarias(uint256 cantidadBruta, bool takeFee) private view returns (TransactionFees memory realFees, TransactionFees memory refractionaryFees)
    {
        if (takeFee) 
        {
           uint256 currentRate = GetConversionRate();

            // Caluclando las tasas
            realFees.TransactionFee = (cantidadBruta * AppliedRatesPercentage.RewardTax) / 100;
            realFees.BurnFee =  (cantidadBruta * AppliedRatesPercentage.BurnTax) / 100;
            realFees.DevFee =  (cantidadBruta * AppliedRatesPercentage.DevelopmentTax) / 100;
            realFees.MarketingFee =  (cantidadBruta * AppliedRatesPercentage.MarketingTax) / 100;
            realFees.LiquidityFee =  (cantidadBruta * AppliedRatesPercentage.LiquidityTax) / 100;

            // Sumando las tasas y agrupando entre las que se van al contrato y las que no
            realFees.TransferrableFee = realFees.DevFee + realFees.MarketingFee + realFees.LiquidityFee;
            realFees.TotalFee = realFees.TransactionFee + realFees.BurnFee + realFees.TransferrableFee;

            refractionaryFees.TransactionFee = realFees.TransactionFee * currentRate;
            refractionaryFees.BurnFee =  realFees.BurnFee * currentRate;
            refractionaryFees.DevFee =   realFees.DevFee * currentRate;
            refractionaryFees.MarketingFee = realFees.MarketingFee * currentRate;
            refractionaryFees.LiquidityFee = realFees.LiquidityFee * currentRate;

            refractionaryFees.TotalFee = realFees.TotalFee * currentRate;
            refractionaryFees.TransferrableFee = realFees.TransferrableFee * currentRate;
        }
    }

    function AccumulateFee(TransactionFees memory realFees, TransactionFees memory refractionaryFees) private 
    {
        BalancesRefraccionarios[address(this)] += refractionaryFees.TransferrableFee;
       
        AccumulatedFeeForDistribution.LiquidityFee += realFees.LiquidityFee;
        
        AccumulatedFeeForDistribution.DevFee += realFees.DevFee;
        
        AccumulatedFeeForDistribution.MarketingFee += realFees.MarketingFee;
        
    }

    function swapTokensForETH(uint256 tokenAmount) private 
    {
        // generate the pair path of token
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = UniswapV2Router.WETH();

        // make the swap
        UniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function swapAndLiquify() private swaping 
    {
        // Swapping the rest of the fees
        if(balanceOf(address(this)) > 0)
        {
            uint256 tokensToSwap = AccumulatedFeeForDistribution.LiquidityFee / 2;
            uint256 tokensForLiquidity = AccumulatedFeeForDistribution.LiquidityFee - tokensToSwap;

            
            swapTokensForETH(AccumulatedFeeForDistribution.DevFee + AccumulatedFeeForDistribution.MarketingFee + tokensToSwap);

            uint256 contractBalance = address(this).balance;
            uint256 devShare = (contractBalance* DevDistributionPct)/100;
            uint256 mktShare = (contractBalance * MarketingDistributionPct)/100;

            DevAddress.transfer(devShare);
            MarketingAddress.transfer(mktShare);

            uint256 eth = address(this).balance;

           UniswapV2Router.addLiquidityETH{value: address(this).balance}(
                address(this),
                tokensForLiquidity,
                0, // slippage is unavoidable
                0, // slippage is unavoidable
                DevAddress,
                block.timestamp
            );

            AccumulatedFeeForDistribution.LiquidityFee = 0;
            AccumulatedFeeForDistribution.DevFee = 0;
            AccumulatedFeeForDistribution.MarketingFee = 0;
           
            TotalSwapped += tokensForLiquidity;


            emit LiquidityAdded(tokensForLiquidity, eth);
        }
    }
 
    function tokenFromReflection(uint256 reflactionaryAmount) public view returns (uint256)
    {
        require(reflactionaryAmount <= ReflactionaryTotal,"Amount must be less than total reflections");
        return reflactionaryAmount / GetConversionRate();
    }

    function GetConversionRate() private view returns (uint256) 
    {
        return ReflactionaryTotal / totalSupply();
    }

    // Funciones para modificar cositas del swap
    function setSwapAndLiquifyEnabled(bool _enabled) public onlyOwner 
    {
        SwapEnabled = _enabled;
        emit SwapAndLiquifyEnabledUpdated(_enabled);
    }


    // Esto es para poder recibir cosas de pancake swap
    receive() external payable {}

}  
