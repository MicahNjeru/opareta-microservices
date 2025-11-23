import { Test, TestingModule } from '@nestjs/testing';
import { AppController } from './app.controller';
import { AppService } from './app.service';

describe('AppController', () => {
  let appController: AppController;
  let appService: AppService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [AppController],
      providers: [
        {
          provide: AppService,
          useValue: {
            getHealth: jest.fn().mockResolvedValue({
              status: 'ok',
              timestamp: expect.any(String),
              service: 'payment-service',
              database: 'connected',
              redis: 'connected',
            }),
          },
        },
      ],
    }).compile();

    appController = module.get<AppController>(AppController);
    appService = module.get<AppService>(AppService);
  });

  it('should call getHealth', async () => {
    await appController.getHealth();
    expect(appService.getHealth).toHaveBeenCalled();
  });
});
