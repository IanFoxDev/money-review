<?php

declare(strict_types=1);

namespace App\Payouts;

/** A thin JSON client for the CardHub API (fictional), with the account's API key. */
interface CardHubApi
{
    /**
     * @param array<string, mixed> $body
     * @param array<string, string> $headers
     * @return array<string, mixed> the decoded response body
     * @throws ProviderTimeout when CardHub does not answer in time or answers 5xx
     */
    public function post(string $path, array $body, array $headers = []): array;

    /**
     * @param array<string, string> $query
     * @return array<string, mixed>
     * @throws ProviderTimeout
     */
    public function get(string $path, array $query = []): array;
}
