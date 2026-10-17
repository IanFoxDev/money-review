<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('installments', function (Blueprint $table) {
            $table->id();
            $table->foreignId('subscription_id');
            $table->unsignedSmallInteger('number');     // 1..months
            $table->date('due_on');                     // charged by ChargeDueInstallments on this day
            $table->bigInteger('amount_cents');
            $table->string('currency', 3);
            $table->string('status');                   // scheduled, pending, paid, failed
            $table->timestamps();
            $table->unique(['subscription_id', 'number']);
        });
    }
};
