<?php

namespace App\Jobs;

use App\Exceptions\GatewayTimeout;
use App\Models\Payout;
use App\Services\PaymentGateway;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Support\Str;

/** Support can retry a payout that is stuck in pending from the admin panel. */
final class RetryFailedPayout implements ShouldQueue
{
    public function __construct(public int $payoutId)
    {
    }

    public function handle(PaymentGateway $gateway): void
    {
        $payout = Payout::findOrFail($this->payoutId);
        if ($payout->status !== 'pending') {
            return;
        }

        $attempts = 0;
        while (true) {
            try {
                $reference = $gateway->payout($payout->partner_id, $payout->amount_cents, $payout->currency, 'payout-retry-'.Str::uuid());
                break;
            } catch (GatewayTimeout $e) {
                if (++$attempts >= 3) {
                    throw $e;
                }
                sleep(2 ** $attempts);
            }
        }

        Payout::whereKey($payout->id)->where('status', 'pending')
            ->update(['status' => 'sent', 'psp_reference' => $reference]);
    }
}
