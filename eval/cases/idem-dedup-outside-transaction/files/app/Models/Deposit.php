<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

final class Deposit extends Model
{
    protected $fillable = ['user_id', 'amount_cents', 'currency', 'bank_reference'];
}
