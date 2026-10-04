<?php

namespace App\Http\Controllers;

use App\Models\Account;
use App\Models\Payment;
use App\Services\Ledger;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/** chargeback.created events. The signature is checked by the VerifyPspSignature middleware. */
final class ChargebackWebhookController
{
    public function __construct(private Ledger $ledger)
    {
    }

    public function __invoke(Request $request): Response
    {
        $reference = (string) $request->input('data.reference');
        $amountCents = (int) $request->input('data.amount_cents');

        DB::transaction(function () use ($reference, $amountCents) {
            $payment = Payment::where('psp_reference', $reference)->lockForUpdate()->firstOrFail();

            // The provider already took the money back: take it from the user's wallet.
            $this->ledger->transfer(
                'chargeback:'.Str::uuid(),
                Account::forUser($payment->user_id, $payment->currency),
                Account::system('chargebacks', $payment->currency),
                $amountCents,
                'chargeback',
            );
        });

        return response()->noContent();
    }
}
