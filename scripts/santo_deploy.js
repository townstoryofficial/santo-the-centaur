async function main() {
    const [deployer] = await ethers.getSigners();
    const beginBalance = await deployer.getBalance();
  
    console.log("Deployer:", deployer.address);
    console.log("Balance:", ethers.utils.formatEther(beginBalance));

    // Deploy
    const santoFactory = await ethers.getContractFactory("SantoTheCentaur");
    const saleStartTime = 1680148800;
    const serverRole = ethers.constants.AddressZero;
    const mysteryURI = "";
    const santoContract = await santoFactory.deploy("SantoTheCentaur", "STC", saleStartTime, serverRole, mysteryURI);
    console.log("SantoTheCentaur Contract:", santoContract.address);

    // +++
    const endBalance = await deployer.getBalance();
    const gasSpend = beginBalance.sub(endBalance);

    console.log("\nLatest balance:", ethers.utils.formatEther(endBalance));
    console.log("Gas:", ethers.utils.formatEther(gasSpend));
  }

  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });