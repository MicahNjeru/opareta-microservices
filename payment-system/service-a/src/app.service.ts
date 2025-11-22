import { Injectable } from '@nestjs/common';
import { InjectDataSource } from '@nestjs/typeorm';
import { DataSource } from 'typeorm';

@Injectable()
export class AppService {
  constructor(
    @InjectDataSource()
    private dataSource: DataSource,
  ) {}

  async getHealth() {
    const dbHealthy = this.dataSource.isInitialized;

    return {
      status: dbHealthy ? 'ok' : 'error',
      timestamp: new Date().toISOString(),
      service: 'auth-service',
      database: dbHealthy ? 'connected' : 'disconnected',
    };
  }
}