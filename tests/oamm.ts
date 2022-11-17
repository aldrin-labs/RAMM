import * as anchor from "@project-serum/anchor";
import { Program } from "@project-serum/anchor";
import { Oamm } from "../target/types/oamm";

describe("oamm", () => {
  // Configure the client to use the local cluster.
  anchor.setProvider(anchor.AnchorProvider.env());

  const program = anchor.workspace.Oamm as Program<Oamm>;

  it("Is initialized!", async () => {
    // Add your test here.
    const tx = await program.methods.initialize().rpc();
    console.log("Your transaction signature", tx);
  });
});
