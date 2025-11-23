import { Module } from '@nestjs/common';
import { HttpModule } from '@nestjs/axios';
import { AuthGuard } from './guards/auth.guard';

@Module({
  imports: [HttpModule],
  providers: [AuthGuard],
  exports: [AuthGuard],
})
export class AuthModule {}