<?php

declare(strict_types=1);

namespace App\Payouts;

use App\Money\Ledger;
use App\Support\RedisLock;
use MongoDB\Client;
use MongoDB\Collection;
use MongoDB\Driver\Session;

use function MongoDB\with_transaction;

/**
 * Monthly partner payouts. One payout per partner and period (the _id), the money is
 * reserved in the in-flight wallet in the same transaction, the provider is called
 * after commit with the payout id as idempotency key.
 */
final class PayoutService
{
    private Collection $payouts;

    public function __construct(
        private Client $client,
        private Ledger $ledger,
        private PayoutProvider $provider,
        private RedisLock $lock,
        string $db = 'billing',
    ) {
        $this->payouts = $client->selectCollection($db, 'payouts');
    }

    public function request(string $partnerId, string $period, int $amount, string $currency): string
    {
        $payoutId = "payout:{$partnerId}:{$period}";
        $session = $this->client->startSession();

        with_transaction($session, function (Session $session) use ($payoutId, $partnerId, $period, $amount, $currency): void {
            if ($this->payouts->findOne(['_id' => $payoutId], ['session' => $session]) !== null) {
                return; // already requested for this period
            }
            $this->payouts->insertOne([
                '_id' => $payoutId,
                'partner_id' => $partnerId,
                'period' => $period,
                'amount' => $amount,
                'currency' => $currency,
                'status' => 'pending',
            ], ['session' => $session]);

            $this->ledger->applyInSession(
                $session,
                $payoutId,
                "partner:{$partnerId}:{$currency}",
                "payouts_in_flight:{$currency}",
                $amount,
                $currency,
            );

            // Instant payouts: send in the same step, so a failure rolls back the reservation.
            $this->provider->send($partnerId, $amount, $currency, $payoutId . ':' . bin2hex(random_bytes(4)));
            $this->payouts->updateOne(['_id' => $payoutId], ['$set' => ['status' => 'sent']], ['session' => $session]);
        });

        return $payoutId;
    }

    /** Sends one pending payout. Run by a scheduler; the lock only avoids duplicate work. */
    public function send(string $payoutId): void
    {
        $token = $this->lock->acquire("payout:{$payoutId}", 60_000);
        if ($token === null) {
            return;
        }

        try {
            // The claim is what makes the send happen once, not the lock.
            $payout = $this->payouts->findOneAndUpdate(
                ['_id' => $payoutId, 'status' => 'pending'],
                ['$set' => ['status' => 'sending', 'sending_at' => new \MongoDB\BSON\UTCDateTime()]],
                ['returnDocument' => \MongoDB\Operation\FindOneAndUpdate::RETURN_DOCUMENT_AFTER],
            );
            if ($payout === null) {
                return;
            }

            try {
                $reference = $this->provider->send($payout['partner_id'], (int) $payout['amount'], $payout['currency'], $payoutId);
            } catch (ProviderTimeout) {
                return; // unknown outcome: stays "sending", resolve() asks the provider later
            } catch (ProviderDeclined) {
                $this->returnFunds($payout);

                return;
            }

            $this->payouts->updateOne(
                ['_id' => $payoutId, 'status' => 'sending'],
                ['$set' => ['status' => 'sent', 'reference' => $reference]],
            );
        } finally {
            $this->lock->release("payout:{$payoutId}", $token);
        }
    }

    /**
     * Settles a payout stuck in "sending" (timeout, or the process died after the call)
     * by asking the provider about the idempotency key. Run by the scheduler for
     * payouts in "sending" for more than ten minutes.
     */
    public function resolve(string $payoutId): void
    {
        $payout = $this->payouts->findOne(['_id' => $payoutId, 'status' => 'sending']);
        if ($payout === null) {
            return;
        }

        $state = $this->provider->status($payoutId);
        if ($state->sent) {
            $this->payouts->updateOne(
                ['_id' => $payoutId, 'status' => 'sending'],
                ['$set' => ['status' => 'sent', 'reference' => $state->reference]],
            );
        } elseif ($state->failed) {
            $this->returnFunds($payout);
        }
        // Otherwise the provider does not know yet: try again on the next run.
    }

    private function returnFunds(array|object $payout): void
    {
        $session = $this->client->startSession();

        with_transaction($session, function (Session $session) use ($payout): void {
            $failed = $this->payouts->updateOne(
                ['_id' => $payout['_id'], 'status' => 'sending'],
                ['$set' => ['status' => 'failed']],
                ['session' => $session],
            );
            if ($failed->getModifiedCount() === 0) {
                return;
            }

            $this->ledger->applyInSession(
                $session,
                'payout-return:' . $payout['_id'],
                "payouts_in_flight:{$payout['currency']}",
                "partner:{$payout['partner_id']}:{$payout['currency']}",
                (int) $payout['amount'],
                $payout['currency'],
            );
        });
    }
}
