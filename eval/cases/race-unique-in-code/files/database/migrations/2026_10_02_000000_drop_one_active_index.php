<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration {
    public function up(): void
    {
        // The service checks for an active subscription itself now.
        DB::statement('DROP INDEX subscriptions_one_active');
    }
};
