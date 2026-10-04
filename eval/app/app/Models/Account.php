<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

final class Account extends Model
{
    protected $fillable = ['owner_type', 'owner_id', 'currency', 'balance_cents', 'allow_negative'];

    public static function forUser(int $userId, string $currency): self
    {
        return self::firstOrCreate(['owner_type' => 'user', 'owner_id' => $userId, 'currency' => $currency]);
    }

    public static function system(string $name, string $currency): self
    {
        return self::where('owner_type', 'system')->where('owner_id', crc32($name))
            ->where('currency', $currency)->firstOrFail();
    }
}
