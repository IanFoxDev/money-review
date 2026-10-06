<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('deposits', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id');
            $table->bigInteger('amount_cents');
            $table->string('currency', 3);
            $table->string('bank_reference');        // typed by the payer, not unique
            $table->timestamps();
            $table->index('bank_reference');
        });
    }
};
