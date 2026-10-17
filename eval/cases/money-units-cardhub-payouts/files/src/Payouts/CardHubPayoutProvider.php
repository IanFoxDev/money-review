<?php

declare(strict_types=1);

namespace App\Payouts;

/**
 * PayoutProvider on CardHub's payouts API, for partners paid by bank transfer in EUR,
 * USD, GBP and JPY. CardHub takes the amount as a decimal string in major units
 * ("125.50") and answers with the payout state: accepted, paid, rejected or returned.
 */
final class CardHubPayoutProvider implements PayoutProvider
{
    private const CURRENCIES = ['EUR', 'USD', 'GBP', 'JPY'];

    public function __construct(private CardHubApi $api)
    {
    }

    public function send(string $partnerId, int $amount, string $currency, string $idempotencyKey): string
    {
        if (! in_array($currency, self::CURRENCIES, true)) {
            throw new ProviderDeclined("CardHub does not pay out in {$currency}");
        }

        $response = $this->api->post('/v2/payouts', [
            'beneficiary_ref' => $partnerId,
            'amount' => self::toDecimal($amount),
            'currency' => $currency,
            'reference' => $idempotencyKey,
        ], ['Idempotency-Key' => $idempotencyKey]);

        $state = strtolower((string) ($response['state'] ?? ''));
        if ($state === 'rejected') {
            throw new ProviderDeclined((string) ($response['reason'] ?? 'rejected by CardHub'));
        }
        if (! in_array($state, ['accepted', 'paid'], true) || ! isset($response['id'])) {
            throw new ProviderTimeout("Unexpected CardHub answer for {$idempotencyKey}");
        }

        return (string) $response['id'];
    }

    public function status(string $idempotencyKey): PayoutState
    {
        $response = $this->api->get('/v2/payouts', ['reference' => $idempotencyKey]);
        $payout = $response['items'][0] ?? null;
        if ($payout === null) {
            return new PayoutState(sent: false, failed: false); // not seen yet
        }

        return match (strtolower((string) $payout['state'])) {
            'accepted', 'paid' => new PayoutState(sent: true, failed: false, reference: (string) $payout['id']),
            'rejected', 'returned' => new PayoutState(sent: false, failed: true),
            default => new PayoutState(sent: false, failed: false),
        };
    }

    /** Minor units to CardHub's decimal string: 12550 -> "125.50". */
    private static function toDecimal(int $minor): string
    {
        $sign = $minor < 0 ? '-' : '';
        $minor = abs($minor);

        return sprintf('%s%d.%02d', $sign, intdiv($minor, 100), $minor % 100);
    }
}
