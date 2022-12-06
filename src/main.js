import Web3 from "web3";
import { newKitFromWeb3 } from "@celo/contractkit";
import BigNumber from "bignumber.js";
import poolAbi from "../contract/pool.abi.json";
import erc20Abi from "../contract/erc20.abi.json";

const ERC20_DECIMALS = 18;
const poolAddress = "0xF4b468A3316d6Fe4d1B2d0350166551D58147052";
const cUSDContractAddress = "0x874069Fa1Eb16D44d622F2e0Ca25eeA172369bC1";

let kit;
let contract;

const connectCeloWallet = async function () {
  if (window.celo) {
    notification("⚠️ Please approve this DApp to use it.");
    try {
      await window.celo.enable();
      notificationOff();

      const web3 = new Web3(window.celo);
      kit = newKitFromWeb3(web3);

      const accounts = await kit.web3.eth.getAccounts();
      kit.defaultAccount = accounts[0];

      contract = new kit.web3.eth.Contract(poolAbi, poolAddress);
    } catch (error) {
      notification(`⚠️ ${error}.`);
    }
  } else {
    notification("⚠️ Please install the CeloExtensionWallet.");
  }
};

function notification(_text) {
  document.querySelector(".alert").style.display = "block";
  document.querySelector("#notification").textContent = _text;
}

function notificationOff() {
  document.querySelector(".alert").style.display = "none";
}

const getBalance = async function () {
  const totalBalance = await kit.getTotalBalance(kit.defaultAccount);

  const cUSDBalance = totalBalance.cUSD.shiftedBy(-ERC20_DECIMALS).toFixed(2);
  document.querySelector("#balance").textContent = cUSDBalance + " cUSD";
};

const getPoolBalance = async function () {
  const poolBalance = await contract.methods
    .stakingBalance(kit.defaultAccount)
    .call();

  let newBalance = new BigNumber(poolBalance);

  document.getElementById("poolbalance").textContent =
    newBalance.shiftedBy(-ERC20_DECIMALS).toFixed(2) + " cUSD";
};

const getclaimable = async function () {
  const yieldbalance = await contract.methods
    .yieldBalance(kit.defaultAccount)
    .call();

  let newBalance = new BigNumber(yieldbalance);

  document.getElementById("yieldbalance").textContent =
    newBalance.shiftedBy(-ERC20_DECIMALS).toFixed(2) + " cUSD";
};

window.addEventListener("load", async () => {
  notification("⌛ Loading...");
  await connectCeloWallet();
  await getBalance();
  await getPoolBalance();
  await getclaimable();
  notificationOff();
});

async function approve(_price) {
  const cUSDContract = new kit.web3.eth.Contract(erc20Abi, cUSDContractAddress);

  const result = await cUSDContract.methods
    .approve(poolAddress, _price)
    .send({ from: kit.defaultAccount });
  return result;
}

document.querySelector("#stakeBtn").addEventListener("click", async (e) => {
  e.preventDefault();

  const params = new BigNumber(document.getElementById("stakeAmount").value)
    .shiftedBy(ERC20_DECIMALS)
    .toString();

  notification("⌛ Waiting for payment approval...");
  try {
    await approve(params);
  } catch (error) {
    notification(`⚠️ ${error}.`);
  }

  notification(
    `⌛ staking "${new BigNumber(params)
      .shiftedBy(-ERC20_DECIMALS)
      .toString()} cUSD"...`
  );

  try {
    const result = await contract.methods
      .stake(params)
      .send({ from: kit.defaultAccount });
  } catch (error) {
    if (!error.status) {
      notification(`⚠️ Unable to stake`);
    }
    return;
  }
  notification(
    `🎉 You successfully added "${new BigNumber(params)
      .shiftedBy(-ERC20_DECIMALS)
      .toString()} cUSD"...`
  );
  getPoolBalance();
});

document.querySelector("#unstakeBtn").addEventListener("click", async (e) => {
  e.preventDefault();

  const params = new BigNumber(document.getElementById("unstakeAmount").value)
    .shiftedBy(ERC20_DECIMALS)
    .toString();

  notification(
    `⌛ unstaking "${new BigNumber(params)
      .shiftedBy(-ERC20_DECIMALS)
      .toString()} cUSD"...`
  );

  try {
    const tx = await contract.methods
      .unstake(params)
      .send({ from: kit.defaultAccount });
  } catch (error) {
    console.log(error);
    if (!error.status) {
      notification(`⚠️ Unable to unstake`);
      document.getElementById("unstakeAmount").value = "";
    }
    return;
  }

  notification(
    `⚠️ Successfully unstake "${new BigNumber(params)
      .shiftedBy(-ERC20_DECIMALS)
      .toString()} cUSD"...`
  );
  getPoolBalance();
});

document.querySelector("#claim").addEventListener("click", async (e) => {
  e.preventDefault();

  notification(`⌛ claiming `);

  try {
    await contract.methods.withdrawYield().send({ from: kit.defaultAccount });
  } catch (error) {
    if (!error.status) {
      notification(`⚠️ Unable to claim`);
    }
    return;
  }

  notification(`⚠️ Successfully claimed yield`);
  getPoolBalance();
  getclaimable();
});
