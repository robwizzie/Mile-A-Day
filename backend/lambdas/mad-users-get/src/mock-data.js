export const userDB = {
	rob: {
		userId: 'rob',
		username: 'Rob',
		appleId: 'robertwiscount@icloud.com',
		workouts: {
			2025: {
				'06': [
					{ activity: 'run', distance: 1, date: '1746849600000' },
					{ activity: 'run', distance: 3, date: '1746849600001' },
					{ activity: 'run', distance: 1, date: '1746849600002' },
					{ activity: 'walk', distance: 1.4, date: '1746849600003' },
					{ activity: 'run', distance: 3.1, date: '1746849600004' },
					{ activity: 'walk', distance: 3, date: '1746849600005' },
					{ activity: 'run', distance: 1, date: '1746849600006' }
				]
			}
		},
		friends: ['dave'],
		competitions: ['abc123']
	},
	dave: {
		userId: 'dave',
		username: 'Dave',
		appleId: 'davidsimmerman@icloud.com',
		workouts: {
			2025: {
				'06': [
					{ activity: 'run', distance: 1, date: '1746849600000' },
					{ activity: 'run', distance: 3, date: '1746849600001' },
					{ activity: 'run', distance: 1, date: '1746849600002' },
					{ activity: 'walk', distance: 1.4, date: '1746849600003' },
					{ activity: 'run', distance: 3.1, date: '1746849600004' },
					{ activity: 'walk', distance: 3, date: '1746849600005' },
					{ activity: 'run', distance: 1, date: '1746849600006' }
				]
			}
		},
		friends: ['rob'],
		competitions: ['abc123']
	}
};

export const competitionDB = {
	abc123: {
		competitionId: 'abc123',
		participants: ['rob', 'dave'],
		startDate: '1746849600000',
		status: 'active',
		goals: [
			{
				activities: ['run', 'walk'],
				distance: 1,
				countPerWeek: 7
			}
		]
	}
};
