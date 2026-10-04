<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

final class Payout extends Model
{
    protected $fillable = ['partner_id', 'period', 'amount_cents', 'currency', 'status', 'psp_reference'];
}
