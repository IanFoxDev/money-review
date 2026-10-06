<?php

namespace App\Http\Controllers;

use App\Models\Account;
use App\Models\Deposit;
use App\Models\Payment;
use App\Services\Ledger;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\DB;

/** Provider events. The signature is checked by the VerifyPspSignature middleware. */
final class PspWebhookController
{
    public function __construct(private Ledger $ledger)
    {
    }

    public function __invoke(Request $request): Response
    {
        $eventId = (string) $request->input('id');
        $type = (string) $request->input('type');

        // Retries of an event we already handled are answered right away, without
        // opening a transaction.
        $seen = DB::table('processed_events')->where('source', 'psp')->where('event_id', $eventId)->exists();
        if ($seen) {
            return response()->noContent();
        }

        match ($type) {
            'payment.succeeded', 'payment.failed' => $this->payment($type, (string) $request->input('data.reference')),
            'bank_transfer.received' => $this->bankTransfer((array) $request->input('data')),
            default => null,
        };

        DB::table('processed_events')->insertOrIgnore(['source' => 'psp', 'event_id' => $eventId, 'created_at' => now()]);

        return response()->noContent();
    }

    private function payment(string $type, string $reference): void
    {
        DB::transaction(function () use ($type, $reference) {
            $payment = Payment::where('psp_reference', $reference)->lockForUpdate()->first();
            if ($payment === null || $payment->status !== 'pending') {
                return; // unknown, late or out of order event, the state already moved
            }
            $payment->status = $type === 'payment.succeeded' ? 'succeeded' : 'failed';
            $payment->save();

            if ($payment->status === 'succeeded') {
                // Top-up: money arrives from the provider's clearing account to the user's wallet.
                $this->ledger->transfer(
                    "payment:{$payment->id}",
                    Account::system('psp_clearing', $payment->currency),
                    Account::forUser($payment->user_id, $payment->currency),
                    $payment->amount_cents,
                    'top_up',
                );
            }
        });
    }

    /**
     * A user paid by bank transfer to the provider's collection account. The payer
     * writes the reference by hand, so one reference can arrive with several transfers.
     *
     * @param array{user_id: int, amount_cents: int, currency: string, bank_reference: string} $data
     */
    private function bankTransfer(array $data): void
    {
        DB::transaction(function () use ($data) {
            $deposit = Deposit::create([
                'user_id' => $data['user_id'],
                'amount_cents' => $data['amount_cents'],
                'currency' => $data['currency'],
                'bank_reference' => $data['bank_reference'],
            ]);
            $this->ledger->transfer(
                "deposit:{$deposit->id}",
                Account::system('psp_clearing', $deposit->currency),
                Account::forUser($deposit->user_id, $deposit->currency),
                $deposit->amount_cents,
                'deposit',
            );
        });
    }
}
